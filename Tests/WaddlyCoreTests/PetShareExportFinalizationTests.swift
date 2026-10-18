import AVFoundation
import Foundation
import os
import Testing
@testable import WaddlyCore

@Test func aFailedFinalizationRemovesTheTerminalPartialMovie() throws {
    let images = try finalizationFixtureImages()
    let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("Waddly-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: movieURL) }
    let partialMovieWasRetained = OSAllocatedUnfairLock(initialState: false)

    #expect(throws: (any Error).self) {
        // Model a writer that ends on a terminal, non-completed status after creating its output. The
        // finalizer runs on the serial export queue, so the writer is quiescent here; cancel it (standing in
        // for a failed finalization, not a hardware fault), then recreate a retained partial because
        // cancelWriting may remove the output itself, and finally deliver the completion the caller waits on.
        try PetShareExporter.writeMovie(
            from: images,
            to: movieURL,
            timeout: .seconds(30),
            cancellation: PetShareExportCancellation(),
            hooks: MovieWriterHooks(finalizeWriter: { writer, completion in
                writer.cancelWriting()
                _ = FileManager.default.createFile(atPath: writer.outputURL.path, contents: Data("partial".utf8))
                let retained = FileManager.default.fileExists(atPath: writer.outputURL.path)
                partialMovieWasRetained.withLock { $0 = retained }
                completion()
            })
        )
    }

    #expect(partialMovieWasRetained.withLock { $0 })
    #expect(!FileManager.default.fileExists(atPath: movieURL.path))
}

@Test func aFinalizerThatWinsDuringTheStopPathRemovesTheTerminalPartialMovie() throws {
    let images = try finalizationFixtureImages()
    let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("Waddly-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: movieURL) }
    let partialMovieWasRetained = OSAllocatedUnfairLock(initialState: false)
    let stopPathEntered = OSAllocatedUnfairLock(initialState: false)
    let deadlineExpired = OSAllocatedUnfairLock(initialState: false)
    let finalizerIsStalled = DispatchSemaphore(value: 0)
    let releaseFinalizer = DispatchSemaphore(value: 0)
    let failSafe = DispatchTime.now()

    #expect(throws: PetShareExportError.timedOut) {
        // Stall the finalizer, let the waiter enter the deadline stop path and enqueue `cancelOnQueue`, then
        // complete the finalizer during the grace period with a terminal, non-completed status. That wins the
        // terminal transition, so `cancelOnQueue` can no longer delete the output; the stop path must.
        try PetShareExporter.writeMovie(
            from: images,
            to: movieURL,
            timeout: .seconds(30),
            cancellation: PetShareExportCancellation(),
            hooks: MovieWriterHooks(
                finalizeWriter: { writer, completion in
                    deadlineExpired.withLock { $0 = true }
                    finalizerIsStalled.signal()
                    _ = releaseFinalizer.wait(timeout: .now() + 5)
                    writer.cancelWriting()
                    _ = FileManager.default.createFile(atPath: writer.outputURL.path, contents: Data("partial".utf8))
                    let retained = FileManager.default.fileExists(atPath: writer.outputURL.path)
                    partialMovieWasRetained.withLock { $0 = retained }
                    completion()
                },
                hasExpired: { _ in
                    if deadlineExpired.withLock({ $0 }) {
                        return true
                    }
                    return DispatchTime.now() > failSafe + .seconds(20)
                },
                willStopWriter: {
                    stopPathEntered.withLock { $0 = true }
                    releaseFinalizer.signal()
                }
            )
        )
    }

    #expect(finalizerIsStalled.wait(timeout: .now()) == .success)
    #expect(stopPathEntered.withLock { $0 })
    #expect(partialMovieWasRetained.withLock { $0 })
    #expect(!FileManager.default.fileExists(atPath: movieURL.path))
}

private func finalizationFixtureImages() throws -> PetImageSet {
    let url = try #require(
        Bundle.module.url(forResource: "nyatinte-bot-3x3", withExtension: "png", subdirectory: "Fixtures")
    )
    return try #require(PetSpriteSheetImporter.frames(from: Data(contentsOf: url)))
}
