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
        defer { closeImageStore(store) }
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
        defer { closeImageStore(store) }
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
        defer { closeImageStore(store) }
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
        defer { closeImageStore(store) }
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
        defer { closeImageStore(store) }
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
        defer { closeImageStore(store) }
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
        defer { closeImageStore(store) }
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

    @Test func restoreKeepsSheetEditingMetadataWithoutResidentPNGData() async throws {
        let store = makeImageStore()
        defer { closeImageStore(store) }
        let directory = try #require(store.directory)
        let candidate = try restoredSheetCandidate()
        try await store.persist(candidate.images)

        store.importedImages = nil
        try await store.restore()

        let editingSource = try #require(store.images.editingSource)
        #expect(editingSource.editing == candidate.editingSource.editing)
        #expect(editingSource.sheetPNGData == nil)
        #expect(editingSource.sheetFileURL == directory.appendingPathComponent("source-sheet.png"))
        #expect(editingSource.loadSheetPNGData() == candidate.sheetPNGData)
    }

    @Test func confirmFromRestoredSheetPreservesSidecarWithoutResidentBytes() async throws {
        let mirror = StoreLegacyMirror()
        let store = makeImageStore(mirror: mirror)
        defer { closeImageStore(store) }
        let directory = try #require(store.directory)
        let candidate = try restoredSheetCandidate()
        try await store.persist(candidate.images)

        let reopened = PetImageStore(
            directory: directory,
            legacyFiles: { mirror.files },
            writeLegacyFiles: { mirror.files = $0 },
            imagesDidChange: { _ in }
        )
        try await reopened.restore()
        var updated = reopened.images
        let adjustment = FrameAdjustment(
            crop: SquareCrop(x: 8, y: 12, size: candidate.cellSize - 16),
            offsetX: 3,
            offsetY: -2
        )
        updated.editingSource?.editing.setAdjustment(adjustment, for: .idle1)

        let outcome = await reopened.confirmPetImage(updated)
        guard case .confirmed = outcome else {
            Issue.record("expected confirm to succeed, got \(outcome)")
            return
        }
        #expect(reopened.images.editingSource?.sheetPNGData == nil)
        let sheetURL = directory.appendingPathComponent("source-sheet.png")
        #expect(try Data(contentsOf: sheetURL) == candidate.sheetPNGData)

        reopened.importedImages = nil
        try await reopened.restore()
        let restoredSource = try #require(reopened.images.editingSource)
        #expect(restoredSource.editing.adjustment(for: .idle1) == adjustment)
        #expect(restoredSource.sheetPNGData == nil)
        #expect(restoredSource.loadSheetPNGData() == candidate.sheetPNGData)
    }

    @Test func persistFromRestoredSheetRemovesSidecarsWhenSheetFileWasDeleted() async throws {
        let store = makeImageStore()
        defer { closeImageStore(store) }
        let directory = try #require(store.directory)
        let candidate = try restoredSheetCandidate()
        try await store.persist(candidate.images)

        store.importedImages = nil
        try await store.restore()
        let sheetURL = directory.appendingPathComponent("source-sheet.png")
        let editsURL = directory.appendingPathComponent("frame-edits.json")
        try FileManager.default.removeItem(at: sheetURL)

        try await store.persist(store.images)

        #expect(store.images.editingSource == nil)
        #expect(!FileManager.default.fileExists(atPath: sheetURL.path))
        #expect(!FileManager.default.fileExists(atPath: editsURL.path))
    }

    @Test func persistFromRestoredSheetCopiesSheetIntoAnotherDirectory() async throws {
        let sourceStore = makeImageStore()
        defer { closeImageStore(sourceStore) }
        let destinationStore = makeImageStore()
        defer { closeImageStore(destinationStore) }
        let destinationDirectory = try #require(destinationStore.directory)
        let candidate = try restoredSheetCandidate()
        try await sourceStore.persist(candidate.images)

        sourceStore.importedImages = nil
        try await sourceStore.restore()

        try await destinationStore.persist(sourceStore.images)

        let destinationSheetURL = destinationDirectory.appendingPathComponent("source-sheet.png")
        #expect(try Data(contentsOf: destinationSheetURL) == candidate.sheetPNGData)
        let copiedSource = try #require(destinationStore.images.editingSource)
        #expect(copiedSource.sheetPNGData == nil)
        #expect(copiedSource.sheetFileURL == destinationSheetURL)
        #expect(copiedSource.loadSheetPNGData() == candidate.sheetPNGData)
    }

    private func restoredSheetCandidate() throws -> PetSheetCandidate {
        let data = try Data(contentsOf: storeExampleSheetURL())
        return try PetSpriteSheetImporter.inspect(data).get()
    }
}
