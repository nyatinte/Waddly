import AppKit

// AVFoundation marks its asset writer classes NS_SWIFT_NONSENDABLE. The export creates them on the
// caller's thread and touches them only on the serial export queue, so `@preconcurrency` suppresses no
// diagnostic that `MovieWriterState`'s documented confinement does not already cover.
@preconcurrency import AVFoundation
import ImageIO
import os
import UniformTypeIdentifiers

private struct ScheduledShot {
    let image: CGImage
    let duration: TimeInterval
}

private struct ShotDefinition {
    let category: PetImageCategory
    let index: Int
    let duration: TimeInterval
}

/// Owns one export's writer and the progress the waiting caller reads.
///
/// `@unchecked Sendable` is sound because the writer, input, and adaptor are created once and then only
/// touched on the serial export queue in `MovieWriterContext`, and because every mutable counter lives
/// behind `progress`, whose lock synchronizes the caller's terminal reads and cancellation requests with
/// the media-data callback. No other instance shares this state.
private final class MovieWriterState: @unchecked Sendable {
    struct Progress: Sendable {
        var frameIndex = 0
        var error: Error?
        var isTerminal = false
        var didCancel = false
    }

    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let shots: [ScheduledShot]
    private let progress = OSAllocatedUnfairLock(initialState: Progress())

    init(
        writer: AVAssetWriter,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        shots: [ScheduledShot]
    ) {
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.shots = shots
    }

    var frameIndex: Int {
        progress.withLock { $0.frameIndex }
    }

    var isTerminal: Bool {
        progress.withLock { $0.isTerminal }
    }

    var recordedError: Error? {
        progress.withLock { $0.error }
    }

    func advanceFrame() {
        progress.withLock { $0.frameIndex += 1 }
    }

    func record(error: any Error) {
        progress.withLock { $0.error = error }
    }

    func markTerminal() {
        progress.withLock { $0.isTerminal = true }
    }

    /// Returns `true` when this call is the one that cancelled the export.
    func beginCancellation() -> Bool {
        progress.withLock { progress in
            guard !progress.didCancel, !progress.isTerminal else { return false }
            progress.didCancel = true
            progress.isTerminal = true
            return true
        }
    }
}

/// Drives one export from the serial queue that owns its writer.
///
/// The caller waits on `finished` while `encodeFrames` fills the writer; `cancelOnQueue` stops the writer
/// on the same queue, so cancellation and completion can never mutate the writer during an append.
private struct MovieWriterContext: Sendable {
    let state: MovieWriterState
    let queue: DispatchQueue
    let finished: DispatchSemaphore
    let cancelOnQueue: @Sendable () -> Void

    /// Fills the writer until it has every frame, backpressure stops it, or the export is cancelled.
    func encodeFrames(cancellation: PetShareExportCancellation) {
        guard !state.isTerminal, !cancellation.isCancelled else { return }
        while state.input.isReadyForMoreMediaData, !cancellation.isCancelled {
            let frameIndex = state.frameIndex
            guard frameIndex < PetShareExporter.movieFrameCount else { break }
            let appended = autoreleasepool {
                let frame = PetShareExporter.frameForExport(state, at: frameIndex)
                guard let buffer = PetShareExporter.makeVideoPixelBuffer(frame: frame, adaptor: state.adaptor)
                else { return false }
                return state.adaptor.append(
                    buffer,
                    withPresentationTime: CMTime(
                        value: Int64(frameIndex),
                        timescale: PetShareExporter.movieFrameRate
                    )
                )
            }
            guard appended else {
                state.record(error: state.writer.error ?? PetShareExportError.frameEncodingFailed)
                state.input.markAsFinished()
                cancelOnQueue()
                return
            }
            state.advanceFrame()
        }
        guard state.frameIndex == PetShareExporter.movieFrameCount else { return }
        state.markTerminal()
        state.input.markAsFinished()
        state.writer.finishWriting { finished.signal() }
    }

    /// Waits for the writer to finish, stopping it when the caller cancels or the timeout expires.
    func waitForWriter(cancellation: PetShareExportCancellation, timeout: DispatchTimeInterval) throws {
        let deadline = DispatchTime.now() + timeout
        while finished.wait(timeout: .now() + PetShareExporter.cancellationPollInterval) == .timedOut {
            guard cancellation.isCancelled || DispatchTime.now() >= deadline else { continue }
            queue.async(execute: cancelOnQueue)
            // Wait for the queue to stop the writer before the caller removes any partial output.
            _ = finished.wait(timeout: .now() + PetShareExporter.cancellationGracePeriod)
            throw cancellation.isCancelled ? PetShareExportError.cancelled : PetShareExportError.timedOut
        }
    }
}

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

/// Schedules the media-data callback that owns the writer. Tests inject a delayed queue to model a stalled encoder.
typealias MediaDataScheduler = @Sendable (AVAssetWriterInput, DispatchQueue, @escaping @Sendable () -> Void) -> Void

public enum PetShareExporter {
    fileprivate static let movieFrameRate: Int32 = 12
    fileprivate static let movieFrameCount = 60
    /// How long a waiting export sleeps before it rechecks its cancellation token.
    fileprivate static let cancellationPollInterval = DispatchTimeInterval.milliseconds(20)
    /// Bounds the wait for the export queue to stop the writer before the caller cleans up the output.
    fileprivate static let cancellationGracePeriod = DispatchTimeInterval.seconds(5)
    private static let movieSize = 384
    private static let scheduleMediaData: MediaDataScheduler = { input, queue, block in
        input.requestMediaDataWhenReady(on: queue, using: block)
    }

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
            scheduleMediaData: scheduleMediaData
        )
    }

    /// `timeout` bounds the wait for a stalled writer, `cancellation` stops an in-flight export, and
    /// `scheduleMediaData` lets tests stall the media-data queue.
    static func writeMovie(
        from images: PetImageSet,
        to url: URL,
        timeout: DispatchTimeInterval,
        cancellation: PetShareExportCancellation,
        scheduleMediaData: MediaDataScheduler
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
            scheduleMediaData: scheduleMediaData
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
        scheduleMediaData: MediaDataScheduler
    ) throws {
        let finished = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "dev.nyatinte.waddly.share-video")
        // Cancellation mutates the writer only through this block: it runs on the queue that owns the
        // writer, so it can never overlap an append.
        let cancelOnQueue: @Sendable () -> Void = {
            guard state.beginCancellation() else { return }
            if state.writer.status == .writing {
                state.writer.cancelWriting()
            }
            try? FileManager.default.removeItem(at: state.writer.outputURL)
            finished.signal()
        }
        let context = MovieWriterContext(
            state: state,
            queue: queue,
            finished: finished,
            cancelOnQueue: cancelOnQueue
        )
        scheduleMediaData(state.input, queue) {
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

    fileprivate static func frameForExport(_ state: MovieWriterState, at frameIndex: Int) -> CGImage {
        let timeline = state.shots.reduce(0) { $0 + $1.duration }
        let elapsed = Double(frameIndex) * timeline / Double(movieFrameCount)
        var cursor = 0.0
        return state.shots.first { shot in
            defer { cursor += shot.duration }
            return elapsed < cursor + shot.duration
        }?.image ?? state.shots[0].image
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
