import AppKit
@preconcurrency import AVFoundation
import ImageIO
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

private final class MovieWriterState: @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let shots: [ScheduledShot]
    var frameIndex = 0
    var error: Error?

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
}

public enum PetShareExporter {
    private static let frameRate: Int32 = 12
    private static let movieFrameCount = 60
    private static let movieSize = 384
    private static let frameOrder: [(PetImageCategory, Int)] = [
        (.idle, 0), (.idle, 1),
        (.typing, 0), (.typing, 1), (.typing, 2), (.typing, 3),
        (.enter, 0), (.sleep, 0), (.sleep, 1)
    ]

    public static func writeMovie(from images: PetImageSet, to url: URL) throws {
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
        try appendMovieFrames(MovieWriterState(writer: writer, input: input, adaptor: adaptor, shots: shots))
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

    private static func appendMovieFrames(_ state: MovieWriterState) throws {
        let finished = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "dev.nyatinte.waddly.share-video")
        state.input.requestMediaDataWhenReady(on: queue) {
            while state.input.isReadyForMoreMediaData, state.frameIndex < movieFrameCount {
                let appended = autoreleasepool {
                    let frame = frameForExport(state)
                    guard let buffer = makeVideoPixelBuffer(frame: frame, adaptor: state.adaptor) else {
                        return false
                    }
                    return state.adaptor.append(
                        buffer,
                        withPresentationTime: CMTime(value: Int64(state.frameIndex), timescale: frameRate)
                    )
                }
                guard appended else {
                    state.error = state.writer.error ?? PetShareExportError.frameEncodingFailed
                    state.input.markAsFinished()
                    state.writer.cancelWriting()
                    finished.signal()
                    return
                }
                state.frameIndex += 1
            }
            guard state.frameIndex == movieFrameCount else { return }
            state.input.markAsFinished()
            state.writer.finishWriting { finished.signal() }
        }
        finished.wait()
        if let error = state.error {
            throw error
        }
        guard state.writer.status == .completed else {
            throw state.writer.error ?? PetShareExportError.writerUnavailable
        }
    }

    private static func frameForExport(_ state: MovieWriterState) -> CGImage {
        let timeline = state.shots.reduce(0) { $0 + $1.duration }
        let elapsed = Double(state.frameIndex) * timeline / Double(movieFrameCount)
        var cursor = 0.0
        return state.shots.first { shot in
            defer { cursor += shot.duration }
            return elapsed < cursor + shot.duration
        }?.image ?? state.shots[0].image
    }

    private static func makeVideoPixelBuffer(
        frame: CGImage,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }
        var optionalBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &optionalBuffer) == kCVReturnSuccess,
              let buffer = optionalBuffer,
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess,
              let baseAddress = CVPixelBufferGetBaseAddress(buffer),
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
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
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
}
