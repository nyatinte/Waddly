import AppKit
import Testing
import WaddlyCore

/// Restore-side store behavior: migration, reconciliation guards, and the failure modes the app
/// surfaces as alerts.
@Suite(.serialized) @MainActor struct PetImageStoreRestoreTests {
    /// A crash between stage and commit leaves newer files without a manifest entry. Restart keeps
    /// the committed set and sweeps only the staged files.
    @Test func restartAfterInterruptedCommitKeepsCommittedSetAndSweepsStagedFiles() async throws {
        let mirror = StoreLegacyMirror()
        let store = makeImageStore(mirror: mirror)
        let images = try storeExampleImages()
        try await store.persist(images)
        let storage = try PetImageStorage(directory: #require(store.directory))
        let committed = try storeCommittedManifest(in: storage)
        let committedFrames = try storeFrameData(in: storage.directory)
        let stagedOnly = try storage.stage(images, replacing: PetImageSet(), files: [:])
        #expect(Set(stagedOnly.values.flatMap(\.self)).isDisjoint(with: Set(committed.values.flatMap(\.self))))

        store.importedImages = nil
        try await store.restore()

        #expect(try storage.readManifest() == committed)
        #expect(try storeFrameData(in: storage.directory) == committedFrames)
        #expect(store.hasCompleteImageSet)
    }

    /// A missing manifest migrates the legacy mirror to disk before the sweep can delete a frame.
    @Test func missingManifestMigratesLegacyMirrorBeforeReconciling() async throws {
        let mirror = StoreLegacyMirror()
        let store = makeImageStore(mirror: mirror)
        let directory = try #require(store.directory)
        let storage = PetImageStorage(directory: directory)
        let legacy = try storage.stage(storeExampleImages(), replacing: PetImageSet(), files: [:])
        mirror.files = legacy
        let orphan = "\(UUID().uuidString).png"
        try Data("orphan".utf8).write(to: directory.appendingPathComponent(orphan))
        #expect(try storage.readManifest() == nil)

        try await store.restore()

        #expect(try storage.readManifest() == legacy)
        #expect(store.hasCompleteImageSet)
        #expect(try storeFrameData(in: directory).count == 9)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(orphan).path))
        #expect(mirror.files == legacy)
    }

    /// No manifest and no legacy mirror: frames of uncertain provenance must survive startup.
    @Test func noManifestAndEmptyMirrorPreservesUnknownFrames() async throws {
        let store = makeImageStore()
        let directory = try #require(store.directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stray = "\(UUID().uuidString).png"
        try Data("stray".utf8).write(to: directory.appendingPathComponent(stray))
        let storage = PetImageStorage(directory: directory)
        #expect(try storage.readManifest() == nil)

        try await store.restore()

        #expect(try storage.readManifest() == nil)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(stray).path))
        #expect(!store.hasCompleteImageSet)
    }

    /// An explicitly committed empty manifest is authoritative and sweeps unknown frames away.
    @Test func emptyCommittedManifestIsAuthoritative() async throws {
        let store = makeImageStore()
        let directory = try #require(store.directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stray = "\(UUID().uuidString).png"
        try Data("stray".utf8).write(to: directory.appendingPathComponent(stray))
        let storage = PetImageStorage(directory: directory)
        try storage.commitManifest([:])

        try await store.restore()

        #expect(try storage.readManifest() == [:])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(stray).path))
        #expect(!store.hasCompleteImageSet)
    }

    /// A frame an older build added after this build's save must survive the next launch.
    @Test func newerFramesFromAnOlderBuildSurviveRestore() async throws {
        let mirror = StoreLegacyMirror()
        let store = makeImageStore(mirror: mirror)
        try await store.persist(storeExampleImages())
        let storage = try PetImageStorage(directory: #require(store.directory))
        let committed = try storeCommittedManifest(in: storage)
        // An older build appends a frame and updates the preferences mirror but not the manifest.
        let added = "\(UUID().uuidString).png"
        try Data("older build frame".utf8).write(to: storage.directory.appendingPathComponent(added))
        mirror.files[PetImageCategory.idle.rawValue, default: []].append(added)
        store.importedImages = nil

        try await store.restore()

        #expect(try storage.readManifest() == committed)
        #expect(FileManager.default.fileExists(atPath: storage.directory.appendingPathComponent(added).path))
        #expect(mirror.files != committed)
        #expect(store.files == committed)
        #expect(store.images[.idle].count == committed[PetImageCategory.idle.rawValue]?.count)
    }

    /// A missing referenced frame skips the sweep even when the mirror and manifest agree.
    @Test func incompleteDecodedSetSkipsSweep() async throws {
        let mirror = StoreLegacyMirror()
        let store = makeImageStore(mirror: mirror)
        try await store.persist(storeExampleImages())
        let storage = try PetImageStorage(directory: #require(store.directory))
        let committed = try storeCommittedManifest(in: storage)
        let missing = try #require(committed[PetImageCategory.enter.rawValue]?.first)
        try FileManager.default.removeItem(at: storage.directory.appendingPathComponent(missing))
        let orphan = "\(UUID().uuidString).png"
        try Data("orphan".utf8).write(to: storage.directory.appendingPathComponent(orphan))
        store.importedImages = nil

        try await store.restore()

        #expect(store.loadFailed)
        #expect(try storage.readManifest() == committed)
        #expect(FileManager.default.fileExists(atPath: storage.directory.appendingPathComponent(orphan).path))
    }

    /// An unreadable manifest keeps the last displayable images, blocks edits, and deletes nothing.
    @Test func corruptManifestBlocksEditsAndDeletesNothing() async throws {
        let mirror = StoreLegacyMirror()
        let store = makeImageStore(mirror: mirror)
        try await store.persist(storeExampleImages())
        let storage = try PetImageStorage(directory: #require(store.directory))
        let committedFrames = try storeFrameData(in: storage.directory)
        let orphan = "\(UUID().uuidString).png"
        let orphanData = Data("orphan".utf8)
        try orphanData.write(to: storage.directory.appendingPathComponent(orphan))
        try Data("{ not json".utf8).write(to: storage.manifestURL)

        do {
            try await store.restore()
            Issue.record("expected the corrupt manifest to throw")
        } catch {
            #expect(error is PetImageManifestError)
        }

        #expect(store.loadFailed)
        #expect(store.loadError is PetImageManifestError)
        var expected = committedFrames
        expected[orphan] = orphanData
        #expect(try storeFrameData(in: storage.directory) == expected)
        #expect(FileManager.default.fileExists(atPath: storage.directory.appendingPathComponent(orphan).path))
        let addition = await store.addImages([URL(fileURLWithPath: "/nonexistent.png")], to: .idle)
        guard case .blocked = addition else {
            Issue.record("expected the load failure to block edits, got \(addition)")
            return
        }
    }
}
