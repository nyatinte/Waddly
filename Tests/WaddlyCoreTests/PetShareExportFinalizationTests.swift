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

private func finalizationFixtureImages() throws -> PetImageSet {
    let url = try #require(
        Bundle.module.url(forResource: "nyatinte-bot-3x3", withExtension: "png", subdirectory: "Fixtures")
    )
    return try #require(PetSpriteSheetImporter.frames(from: Data(contentsOf: url)))
}
