import AppKit
import Testing
@testable import WaddlyCore

/// Store behavior for a missing directory and for the add-images outcome the app maps to its
/// alerts. The transaction suites live in `PetImageStoreTests` and `PetImageStoreRestoreTests`.
@Suite(.serialized) @MainActor struct PetImageStoreEditTests {
    /// A store without a directory restores as a no-op instead of reaching any default location.
    @Test func restoreWithoutDirectoryIsANoOp() async throws {
        let store = PetImageStore(
            directory: nil,
            legacyFiles: { [:] },
            writeLegacyFiles: { _ in },
            imagesDidChange: { _ in }
        )

        try await store.restore()

        #expect(store.directory == nil)
        #expect(store.files.isEmpty)
        #expect(!store.hasCompleteImageSet)
    }

    /// A store without a directory refuses to save rather than guessing one.
    @Test func persistWithoutDirectoryThrows() async throws {
        let store = PetImageStore(
            directory: nil,
            legacyFiles: { [:] },
            writeLegacyFiles: { _ in },
            imagesDidChange: { _ in }
        )

        do {
            try await store.persist(storeExampleImages())
            Issue.record("expected a missing directory to throw")
        } catch {
            #expect(error is CocoaError)
        }
        #expect(store.directory == nil)
    }

    /// One decodable URL commits and one undecodable URL is reported as skipped.
    @Test func addImagesReportsAddedAndSkipped() async throws {
        let store = makeImageStore()
        defer { closeImageStore(store) }
        let directory = try #require(store.directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sheet = try storeExampleSheetURL()
        let invalid = directory.appendingPathComponent("invalid.png")
        try Data("not a png".utf8).write(to: invalid)

        let outcome = await store.addImages([sheet, invalid], to: .idle)

        guard case let .added(skipped) = outcome else {
            Issue.record("expected one added frame, got \(outcome)")
            return
        }
        #expect(skipped == 1)
        #expect(store.images[.idle].count == 1)
    }

    /// Only undecodable URLs leave the set unchanged and report nothing was added.
    @Test func addImagesReportsSkippedAll() async throws {
        let store = makeImageStore()
        defer { closeImageStore(store) }
        let directory = try #require(store.directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invalid = directory.appendingPathComponent("invalid.png")
        try Data("not a png".utf8).write(to: invalid)

        let outcome = await store.addImages([invalid], to: .idle)

        guard case .skippedAll = outcome else {
            Issue.record("expected every URL to be skipped, got \(outcome)")
            return
        }
        #expect(store.images[.idle].isEmpty)
    }

    /// A move transaction reports a failed commit through `onSaveError` and leaves the order alone.
    @Test func moveReportsSaveFailureWithoutChangingOrder() async throws {
        let store = makeImageStore()
        defer { closeImageStore(store) }
        try await store.persist(storeExampleImages())
        let storage = try PetImageStorage(directory: #require(store.directory))
        let before = store.images[.idle]
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: storage.manifestURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: storage.manifestURL.path) }

        let reported = StoreFailureRecorder()
        await store.moveImage(from: 0, to: 1, in: .idle) { error in
            reported.errors.append(error)
        }?.value

        #expect(reported.errors.count == 1)
        #expect(reported.errors.first is PetImageManifestError)
        let after = store.images[.idle]
        #expect(after[0] === before[0])
        #expect(after[1] === before[1])
    }
}
