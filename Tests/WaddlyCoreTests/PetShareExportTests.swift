import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import os
import Testing
import UniformTypeIdentifiers
@testable import WaddlyCore

@Test func shareMovieExportsFiveSecondsOfThePetAnimation() async throws {
    let images = try fixtureImages()
    let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("Waddly-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: movieURL) }

    try PetShareExporter.writeMovie(from: images, to: movieURL)
    let asset = AVURLAsset(url: movieURL)
    let duration = try await asset.load(.duration)
    let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let size = try await videoTrack.load(.naturalSize)

    #expect(abs(CMTimeGetSeconds(duration) - 5) < 0.1)
    #expect(size == CGSize(width: 384, height: 384))
}

@Test func shareSpriteSheetExportsTheCanonicalNineFramesAsTransparentPNG() throws {
    let images = try fixtureImages()
    let png = try #require(PetShareExporter.spriteSheetPNG(from: images))
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
    let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
    let exported = try #require(PetSpriteSheetImporter.frames(from: png))

    #expect(width == 768)
    #expect(height == 768)
    #expect(exported.isComplete)
    #expect(exported[.idle].count == 2)
    #expect(exported[.typing].count == 4)
    #expect(exported[.enter].count == 1)
    #expect(exported[.sleep].count == 2)
    for category in PetImageCategory.allCases {
        for index in images[category].indices {
            #expect(try rgbaSHA256(exported[category][index]) == rgbaSHA256(images[category][index]))
        }
    }
}

@Test func shareExportsSupportReducedFrameCountsAndMixedDimensions() async throws {
    var images = try fixtureImages()
    let context = try #require(CGContext(
        data: nil,
        width: 96,
        height: 48,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 96, height: 48))
    let nonSquareImage = try NSImage(
        cgImage: #require(context.makeImage()),
        size: NSSize(width: 96, height: 48)
    )
    images[.idle] = [images[.idle][0]]
    images[.typing] = [nonSquareImage]
    images[.sleep] = [images[.sleep][0]]

    let spriteData = try #require(PetShareExporter.spriteSheetPNG(from: images))
    let spriteImages = try #require(PetSpriteSheetImporter.frames(from: spriteData))
    #expect(spriteImages.isComplete)
    #expect(spriteImages[.idle].count == 2)
    #expect(spriteImages[.typing].count == 4)
    let idleRaster = try #require(spriteImages[.idle][0].cgImage(forProposedRect: nil, context: nil, hints: nil))
    let typingRaster = try #require(spriteImages[.typing][0].cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(typingRaster.width == idleRaster.width)

    let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("Waddly-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: movieURL) }
    try PetShareExporter.writeMovie(from: images, to: movieURL)
    let duration = try await AVURLAsset(url: movieURL).load(.duration)
    #expect(abs(CMTimeGetSeconds(duration) - 5) < 0.1)
}

private func fixtureImages() throws -> PetImageSet {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "nyatinte-bot-3x3",
            withExtension: "png",
            subdirectory: "Fixtures"
        )
    )
    return try #require(PetSpriteSheetImporter.frames(from: Data(contentsOf: fixtureURL)))
}

private func exportMovie(
    from images: PetImageSet,
    to url: URL,
    timeout: DispatchTimeInterval,
    cancellation: PetShareExportCancellation = PetShareExportCancellation(),
    hooks: MovieWriterHooks = MovieWriterHooks()
) throws {
    try PetShareExporter.writeMovie(
        from: images,
        to: url,
        timeout: timeout,
        cancellation: cancellation,
        hooks: hooks
    )
}

private func waitUntil(_ condition: () -> Bool, within seconds: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() {
            return true
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return condition()
}

@Test func deadlineCleansUpWithoutAResultingReadinessCallback() throws {
    let images = try fixtureImages()
    let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("Waddly-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: movieURL) }
    let readinessCallbackRan = DispatchSemaphore(value: 0)

    #expect(throws: PetShareExportError.timedOut) {
        // Model an encoder whose readiness callback arrives long after the deadline: cleanup cannot depend on one.
        try PetShareExporter.writeMovie(
            from: images,
            to: movieURL,
            timeout: .milliseconds(50),
            cancellation: PetShareExportCancellation(),
            hooks: MovieWriterHooks(scheduleMediaData: { _, queue, block in
                queue.asyncAfter(deadline: .now() + .seconds(2)) {
                    block()
                    readinessCallbackRan.signal()
                }
            })
        )
    }

    #expect(readinessCallbackRan.wait(timeout: .now()) == .timedOut)
    #expect(readinessCallbackRan.wait(timeout: .now() + 10) == .success)
    #expect(!FileManager.default.fileExists(atPath: movieURL.path))
}

@Test func deadlineDuringEncodingLeavesNoPartialMovie() throws {
    let images = try fixtureImages()
    let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("Waddly-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: movieURL) }

    // The deadline is controlled, not raced: the media-data callback starts after the timeout would expire,
    // yet expiration waits for a known, nonterminal appended frame. A wall-clock deadline would cancel here
    // before any frame existed.
    let framesWritten = OSAllocatedUnfairLock(initialState: 0)
    let progressBeforeExpiry = OSAllocatedUnfairLock(initialState: false)
    let deadlineExpired = OSAllocatedUnfairLock(initialState: false)
    let encodingStarted = DispatchSemaphore(value: 0)
    let releaseEncode = DispatchSemaphore(value: 0)
    let failSafe = DispatchTime.now()

    #expect(throws: PetShareExportError.timedOut) {
        try exportMovie(
            from: images,
            to: movieURL,
            timeout: .milliseconds(100),
            hooks: MovieWriterHooks(
                scheduleMediaData: { input, queue, block in
                    queue.asyncAfter(deadline: .now() + .milliseconds(300)) {
                        input.requestMediaDataWhenReady(on: queue, using: block)
                    }
                },
                afterFrameAppended: { frameCount in
                    framesWritten.withLock { $0 = frameCount }
                    encodingStarted.signal()
                    // Progress is known and nonterminal; only now may the deadline expire.
                    deadlineExpired.withLock { $0 = true }
                    _ = releaseEncode.wait(timeout: .now() + 5)
                    return false
                },
                hasExpired: { _ in
                    if deadlineExpired.withLock({ $0 }) {
                        return true
                    }
                    // Bounded fail-safe: a starved encoder fails the test instead of hanging it.
                    return DispatchTime.now() > failSafe + .seconds(20)
                },
                willStopWriter: {
                    progressBeforeExpiry.withLock { $0 = framesWritten.withLock { $0 } >= 1 }
                    releaseEncode.signal()
                }
            )
        )
    }

    // The callback started after the timeout, yet expiration waited for the first appended frame.
    #expect(framesWritten.withLock { $0 } == 1)
    #expect(progressBeforeExpiry.withLock { $0 })
    #expect(encodingStarted.wait(timeout: .now()) == .success)
    // The deadline path ended the export; it did not wait out the cancellation grace period.
    #expect(DispatchTime.now() < failSafe + .seconds(5))
    // Cancelling the partial writer removes the output it had begun.
    #expect(waitUntil({ !FileManager.default.fileExists(atPath: movieURL.path) }, within: 10))
}

@Test func cancellationBeforeTheFirstAppendStopsTheExportAndRemovesTheOutput() throws {
    let images = try fixtureImages()
    let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("Waddly-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: movieURL) }
    let cancellation = PetShareExportCancellation()
    let start = DispatchTime.now()

    #expect(throws: PetShareExportError.cancelled) {
        // The dialog closed between starting the writer and the first media-data callback.
        try PetShareExporter.writeMovie(
            from: images,
            to: movieURL,
            timeout: .seconds(30),
            cancellation: cancellation,
            hooks: MovieWriterHooks(scheduleMediaData: { input, queue, block in
                cancellation.cancel()
                input.requestMediaDataWhenReady(on: queue, using: block)
            })
        )
    }

    // Cancellation must not wait for the export timeout, and the cancelled export leaves no movie.
    #expect(DispatchTime.now() < start + .seconds(5))
    #expect(!FileManager.default.fileExists(atPath: movieURL.path))
}

@Test func cancellationAfterTheFirstEncodedFramesRemovesThePartialMovie() throws {
    let images = try fixtureImages()
    let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("Waddly-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: movieURL) }
    let cancellation = PetShareExportCancellation()
    let cancelledAtFrame = OSAllocatedUnfairLock<Int?>(initialState: nil)
    let partialMovieWasOnDisk = OSAllocatedUnfairLock(initialState: false)

    #expect(throws: PetShareExportError.cancelled) {
        // The dialog closes after the encoder has already written frames, not before the first one. The
        // hook cancels at a known, nonterminal frame, so the encoder cannot reach the end of the movie first.
        try PetShareExporter.writeMovie(
            from: images,
            to: movieURL,
            timeout: .seconds(30),
            cancellation: cancellation,
            hooks: MovieWriterHooks(afterFrameAppended: { frameCount in
                guard frameCount == 3 else { return true }
                cancelledAtFrame.withLock { $0 = frameCount }
                partialMovieWasOnDisk.withLock {
                    $0 = FileManager.default.fileExists(atPath: movieURL.path)
                }
                cancellation.cancel()
                return true
            })
        )
    }

    #expect(cancelledAtFrame.withLock { $0 } == 3)
    #expect(partialMovieWasOnDisk.withLock { $0 })
    #expect(!FileManager.default.fileExists(atPath: movieURL.path))
}

@Test func cancellingWhileTheWriterIsFinishingStopsItAndRemovesThePartialMovie() throws {
    let images = try fixtureImages()
    let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("Waddly-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: movieURL) }
    let cancellation = PetShareExportCancellation()
    let sawPartialMovie = DispatchSemaphore(value: 0)
    let start = DispatchTime.now()

    #expect(throws: PetShareExportError.cancelled) {
        // Model an encoder that never completes finishWriting while every frame is already written.
        try PetShareExporter.writeMovie(
            from: images,
            to: movieURL,
            timeout: .seconds(30),
            cancellation: cancellation,
            hooks: MovieWriterHooks(finalizeWriter: { writer, _ in
                if FileManager.default.fileExists(atPath: writer.outputURL.path) {
                    sawPartialMovie.signal()
                }
                cancellation.cancel()
            })
        )
    }

    // The stalled writer is cancelled instead of being left to run through the grace period.
    #expect(DispatchTime.now() < start + .seconds(2))
    #expect(sawPartialMovie.wait(timeout: .now()) == .success)
    #expect(!FileManager.default.fileExists(atPath: movieURL.path))
}

@Test func aCancellationThatLosesTheRaceToCompletionKeepsTheFinishedMovie() async throws {
    let images = try fixtureImages()
    let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("Waddly-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: movieURL) }
    let cancellation = PetShareExportCancellation()

    #expect(throws: PetShareExportError.cancelled) {
        // Model a completion the caller never observes: the movie is complete on disk when the dialog
        // closes, so cancellation must not delete it.
        try PetShareExporter.writeMovie(
            from: images,
            to: movieURL,
            timeout: .seconds(30),
            cancellation: cancellation,
            hooks: MovieWriterHooks(finalizeWriter: { writer, _ in
                let writerFinished = DispatchSemaphore(value: 0)
                writer.finishWriting { writerFinished.signal() }
                _ = writerFinished.wait(timeout: .now() + .seconds(10))
                cancellation.cancel()
            })
        )
    }

    let duration = try await AVURLAsset(url: movieURL).load(.duration)
    #expect(abs(CMTimeGetSeconds(duration) - 5) < 0.1)
}

@Test func moviePixelBufferConstructionFailsWhenThePoolIsUnavailable() throws {
    let frame = try #require(fixtureImages()[.idle].first?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 384,
            AVVideoHeightKey: 384
        ]),
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
    )

    #expect(PetShareExporter.makeVideoPixelBuffer(frame: frame, adaptor: adaptor) == nil)
}

private func rgbaSHA256(_ image: NSImage) throws -> String {
    let raster = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let bytesPerRow = raster.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * raster.height)
    return try pixels.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(
            data: buffer.baseAddress,
            width: raster.width,
            height: raster.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(raster, in: CGRect(x: 0, y: 0, width: raster.width, height: raster.height))
        return SHA256.hash(data: Data(buffer)).map { String(format: "%02x", $0) }.joined()
    }
}
