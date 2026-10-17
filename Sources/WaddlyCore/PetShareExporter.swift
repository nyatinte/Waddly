import AppKit
import AVFoundation
import ImageIO
import os
import UniformTypeIdentifiers

/// Cancels one in-flight export.
///
/// The share window controller owns a token, sets it when the dialog closes, and the export observes it
/// while waiting for the writer. The lock lets the closing main actor and the export queue share the flag
/// without an `@unchecked Sendable` conformance.
public final class PetShareExportCancellation: Sendable {
    private let cancelled = OSAllocatedUnfairLock(initialState: false)

    public init() {}

    public func cancel() {
        cancelled.withLock { $0 = true }
    }

    public var isCancelled: Bool {
        cancelled.withLock { $0 }
    }
}

private struct ShotDefinition {
    let category: PetImageCategory
    let index: Int
    let duration: TimeInterval
}

public enum PetShareExporter {
    private static let movieSize = 384

    private static let frameOrder: [(PetImageCategory, Int)] = [
        (.idle, 0), (.idle, 1),
        (.typing, 0), (.typing, 1), (.typing, 2), (.typing, 3),
        (.enter, 0), (.sleep, 0), (.sleep, 1)
    ]

    public static func writeMovie(
        from images: PetImageSet,
        to url: URL,
        cancellation: PetShareExportCancellation = PetShareExportCancellation()
    ) throws {
        // Only a wedged encoder reaches this bound; a full export takes about a second here.
        try writeMovie(
            from: images,
            to: url,
            timeout: .seconds(120),
            cancellation: cancellation,
            hooks: MovieWriterHooks()
        )
    }

    /// `timeout` bounds the wait for a stalled writer, `cancellation` stops an in-flight export, and
    /// `hooks` lets tests stall the encoder's asynchronous steps.
    static func writeMovie(
        from images: PetImageSet,
        to url: URL,
        timeout: DispatchTimeInterval,
        cancellation: PetShareExportCancellation,
        hooks: MovieWriterHooks
    ) throws {
        let shots = try scheduledShots(from: images)
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: movieSize,
            AVVideoHeightKey: movieSize
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: movieSize,
                kCVPixelBufferHeightKey as String: movieSize,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(input) else { throw PetShareExportError.writerUnavailable }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? PetShareExportError.writerUnavailable }
        writer.startSession(atSourceTime: .zero)
        try appendMovieFrames(
            MovieWriterState(writer: writer, input: input, adaptor: adaptor, shots: shots),
            cancellation: cancellation,
            timeout: timeout,
            hooks: hooks
        )
    }

    public static func spriteSheetPNG(from images: PetImageSet) -> Data? {
        guard images.isComplete else { return nil }
        let frames = frameOrder.compactMap { category, index -> CGImage? in
            let categoryImages = images[category]
            guard let image = categoryImages[min(index, categoryImages.count - 1)]
                .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return image
        }
        guard frames.count == frameOrder.count,
              let cellSize = frames.map({ max($0.width, $0.height) }).max(),
              let context = CGContext(
                  data: nil,
                  width: cellSize * 3,
                  height: cellSize * 3,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: cellSize * 3, height: cellSize * 3))

        for (index, frame) in frames.enumerated() {
            let cell = CGRect(
                x: (index % 3) * cellSize,
                y: (2 - index / 3) * cellSize,
                width: cellSize,
                height: cellSize
            )
            context.setBlendMode(.copy)
            context.draw(frame, in: aspectFitRect(for: frame, inside: cell))
        }
        guard let sheet = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, sheet, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func scheduledShots(from images: PetImageSet) throws -> [ScheduledShot] {
        let order: [ShotDefinition] = [
            ShotDefinition(category: .idle, index: 0, duration: 1.5),
            ShotDefinition(category: .idle, index: 1, duration: 0.5),
            ShotDefinition(category: .typing, index: 0, duration: 0.32),
            ShotDefinition(category: .typing, index: 1, duration: 0.32),
            ShotDefinition(category: .typing, index: 2, duration: 0.32),
            ShotDefinition(category: .typing, index: 3, duration: 0.32),
            ShotDefinition(category: .enter, index: 0, duration: 0.9),
            ShotDefinition(category: .sleep, index: 0, duration: 1.2),
            ShotDefinition(category: .sleep, index: 1, duration: 1.6)
        ]
        guard images.isComplete else { throw PetShareExportError.incompleteImageSet }
        let shots = order.compactMap { shot -> ScheduledShot? in
            let categoryImages = images[shot.category]
            guard let image = categoryImages[min(shot.index, categoryImages.count - 1)]
                .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return ScheduledShot(image: image, duration: shot.duration)
        }
        guard shots.count == order.count else { throw PetShareExportError.incompleteImageSet }
        return shots
    }

    private static func appendMovieFrames(
        _ state: MovieWriterState,
        cancellation: PetShareExportCancellation,
        timeout: DispatchTimeInterval,
        hooks: MovieWriterHooks
    ) throws {
        let finished = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "dev.nyatinte.waddly.share-video")
        // Exactly one path ends the export. Cancellation mutates the writer only through this block,
        // which runs on the queue that owns the writer, so it can never overlap an append.
        let cancelOnQueue: @Sendable () -> Void = {
            guard state.endExport() else { return }
            // cancelWriting() is a no-op once the writer failed or completed. Deleting the output is
            // limited to writers that did not complete, so a cancellation that loses the race to
            // finishWriting cannot destroy a finished movie.
            if state.writer.status == .writing {
                state.writer.cancelWriting()
            }
            if state.writer.status != .completed {
                try? FileManager.default.removeItem(at: state.writer.outputURL)
            }
            finished.signal()
        }
        let context = MovieWriterContext(
            state: state,
            queue: queue,
            finished: finished,
            hooks: hooks,
            cancelOnQueue: cancelOnQueue
        )
        hooks.scheduleMediaData(state.input, queue) {
            context.encodeFrames(cancellation: cancellation)
        }
        try context.waitForWriter(cancellation: cancellation, timeout: timeout)
        if let error = state.recordedError {
            throw error
        }
        guard state.writer.status == .completed else {
            throw state.writer.error ?? PetShareExportError.writerUnavailable
        }
    }

    static func makeVideoPixelBuffer(
        frame: CGImage,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }
        var optionalBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &optionalBuffer) == kCVReturnSuccess,
              let buffer = optionalBuffer,
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess
        else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                  data: baseAddress,
                  width: movieSize,
                  height: movieSize,
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                      | CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(red: 0.91, green: 0.93, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: movieSize, height: movieSize))
        context.interpolationQuality = .none
        let contentRect = CGRect(x: 48, y: 48, width: movieSize - 96, height: movieSize - 96)
        context.draw(frame, in: aspectFitRect(for: frame, inside: contentRect))
        return buffer
    }

    private static func aspectFitRect(for image: CGImage, inside rect: CGRect) -> CGRect {
        let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

public enum PetShareExportError: Error {
    case incompleteImageSet
    case writerUnavailable
    case frameEncodingFailed
    case timedOut
    case cancelled
}
