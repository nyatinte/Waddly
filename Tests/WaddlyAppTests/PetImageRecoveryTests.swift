import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct PetImageRecoveryTests {
    /// A missing manifest migrates the legacy defaults to disk before the sweep can delete a frame.
    @Test func missingDiskManifestMigratesLegacyDefaultsBeforeReconciling() async throws {
        let fixture = try AppTestFixture()
        defer { fixture.close() }
        let app = fixture.app
        let storage = PetImageStorage(directory: fixture.directory)
        let legacy = try storage.stage(fixture.exampleImages(), replacing: PetImageSet(), files: [:])
        app.settings.petImageFiles = legacy
        let orphan = "\(UUID().uuidString).png"
        try Data("orphan".utf8).write(to: fixture.directory.appendingPathComponent(orphan))
        #expect(try storage.readManifest() == nil)

        await app.loadSavedPetImage()

        #expect(try storage.readManifest() == legacy)
        #expect(app.hasCompletePetImageSet)
        #expect(try fixture.frameData().count == 9)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(orphan).path))
        #expect(app.settings.petImageFiles == legacy)
    }

    /// No manifest and no legacy mirror: frames of uncertain provenance must survive startup.
    @Test func noManifestAndEmptyLegacyPreservesUnknownFrames() async throws {
        let fixture = try AppTestFixture()
        defer { fixture.close() }
        let app = fixture.app
        let storage = PetImageStorage(directory: fixture.directory)
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let stray = "\(UUID().uuidString).png"
        try Data("stray".utf8).write(to: fixture.directory.appendingPathComponent(stray))
        #expect(app.settings.petImageFiles.isEmpty)
        #expect(try storage.readManifest() == nil)

        await app.loadSavedPetImage()

        // No empty manifest is committed, so the sweep sees `nil` and leaves the frame alone.
        #expect(try storage.readManifest() == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(stray).path))
        #expect(!app.hasCompletePetImageSet)
    }

    /// An explicitly committed empty manifest is authoritative and sweeps unknown frames away.
    @Test func explicitEmptyManifestIsAuthoritative() async throws {
        let fixture = try AppTestFixture()
        defer { fixture.close() }
        let app = fixture.app
        let storage = PetImageStorage(directory: fixture.directory)
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let stray = "\(UUID().uuidString).png"
        try Data("stray".utf8).write(to: fixture.directory.appendingPathComponent(stray))
        let empty: [String: [String]] = [:]
        try storage.commitManifest(empty)
        #expect(try storage.readManifest() == empty)

        await app.loadSavedPetImage()

        #expect(try storage.readManifest() == empty)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(stray).path))
        #expect(!app.hasCompletePetImageSet)
    }

    /// A crash between stage and commit leaves newer files without a manifest entry. Restart keeps
    /// the committed set and sweeps only the staged files.
    @Test func restartAfterInterruptedCommitKeepsCommittedSetAndSweepsStagedFiles() async throws {
        let fixture = try AppTestFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        let storage = PetImageStorage(directory: fixture.directory)
        let storedManifest = try storage.readManifest()
        let committed = try #require(storedManifest)
        let committedFrames = try fixture.frameData()
        let stagedOnly = try storage.stage(fixture.exampleImages(), replacing: PetImageSet(), files: [:])
        #expect(Set(stagedOnly.values.flatMap(\.self)).isDisjoint(with: Set(committed.values.flatMap(\.self))))

        app.importedImages = nil
        await app.loadSavedPetImage()

        #expect(try storage.readManifest() == committed)
        #expect(try fixture.frameData() == committedFrames)
        #expect(app.hasCompletePetImageSet)
    }

    /// An unreadable manifest keeps the last displayable images, blocks edits, and deletes nothing.
    @Test func corruptManifestBlocksEditsAndCleanup() async throws {
        let fixture = try AppTestFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        let storage = PetImageStorage(directory: fixture.directory)
        let committedFrames = try fixture.frameData()
        let orphan = "\(UUID().uuidString).png"
        let orphanData = Data("orphan".utf8)
        try orphanData.write(to: fixture.directory.appendingPathComponent(orphan))
        try Data("{ not json".utf8).write(to: storage.manifestURL)

        app.showSetupWizard()
        let load = Task { await app.loadSavedPetImage() }
        let sheet = try await waitForSheet(app)
        sheet.sheetParent?.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        await load.value

        #expect(app.imageLoadFailed)
        var expectedFrames = committedFrames
        expectedFrames[orphan] = orphanData
        #expect(try fixture.frameData() == expectedFrames)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(orphan).path))
        let removal = try #require(app.removeImage(at: 0, from: .idle))
        await removal.value
        #expect(app.petImages[.idle].count == 2)
    }

    /// A failed commit keeps the previous manifest and images and removes only the new staged files.
    @Test func failedCommitRollsBackStagedFilesAndPreservesCommittedState() async throws {
        let fixture = try AppTestFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        let storage = PetImageStorage(directory: fixture.directory)
        let storedManifest = try storage.readManifest()
        let committed = try #require(storedManifest)
        let committedFrames = try fixture.frameData()
        let committedIdle = app.petImages[.idle].count
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: storage.manifestURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: storage.manifestURL.path) }

        do {
            try await app.persistPetImages(fixture.exampleImages(), resetActivity: true)
            Issue.record("expected the commit to fail")
        } catch {
            #expect(error is PetImageManifestError)
        }

        #expect(try storage.readManifest() == committed)
        #expect(try fixture.frameData() == committedFrames)
        #expect(app.settings.petImageFiles == committed)
        #expect(app.petImages[.idle].count == committedIdle)
        #expect(app.hasCompletePetImageSet)
    }

    /// The manifest commit and the published UI state land before cleanup starts.
    @Test func saveCommitsAndPublishesBeforeCleanup() async throws {
        let fixture = try AppTestFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        let storage = PetImageStorage(directory: fixture.directory)
        app.importedImages = nil
        await app.loadSavedPetImage()
        let slimmer = PetImageSet([.idle: [app.petImages[.idle][0]]])
        let (started, startSignal) = AsyncStream<Void>.makeStream()
        let (release, releaseSignal) = AsyncStream<Void>.makeStream()
        let save = Task {
            try await app.persistPetImages(slimmer, cleanup: { _ in
                startSignal.yield()
                for await _ in release {
                    break
                }
            })
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()

        let storedManifest = try storage.readManifest()
        let committed = try #require(storedManifest)
        #expect(committed == app.settings.petImageFiles)
        #expect(committed.keys.sorted() == [PetImageCategory.idle.rawValue])
        #expect(committed[PetImageCategory.idle.rawValue]?.count == 1)
        #expect(app.petImages[.idle].count == 1)
        // Cleanup has not run yet, so the unreferenced frames are still on disk.
        #expect(try fixture.frameData().count == 9)

        releaseSignal.yield()
        releaseSignal.finish()
        startSignal.finish()
        try await save.value
    }

    /// A frame an older build added after this build's save must survive the next launch.
    @Test func newerFramesFromAnOlderBuildSurviveLaunch() async throws {
        let fixture = try AppTestFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        let storage = PetImageStorage(directory: fixture.directory)
        let stored = try storage.readManifest()
        let committed = try #require(stored)
        // An older build appends a frame and updates the preferences mirror but not the manifest.
        let added = "\(UUID().uuidString).png"
        try Data("older build frame".utf8).write(to: fixture.directory.appendingPathComponent(added))
        var olderMirror = app.settings.petImageFiles
        olderMirror["idle", default: []].append(added)
        app.settings.petImageFiles = olderMirror
        app.importedImages = nil

        await app.loadSavedPetImage()

        // Disk stays authoritative, and the disagreement skips the sweep.
        #expect(try storage.readManifest() == committed)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(added).path))
        #expect(app.settings.petImageFiles == olderMirror)
        #expect(app.storedImageFiles == committed)
        #expect(app.petImages[.idle].count == committed["idle"]?.count)
    }

    /// A missing referenced frame skips the sweep even when the mirror and manifest agree.
    @Test func incompleteDecodedSetSkipsCleanup() async throws {
        let fixture = try AppTestFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        let storage = PetImageStorage(directory: fixture.directory)
        let stored = try storage.readManifest()
        let committed = try #require(stored)
        let missing = try #require(committed["enter"]?.first)
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent(missing))
        let orphan = "\(UUID().uuidString).png"
        try Data("orphan".utf8).write(to: fixture.directory.appendingPathComponent(orphan))
        app.importedImages = nil

        await app.loadSavedPetImage()

        #expect(app.imageLoadFailed)
        #expect(try storage.readManifest() == committed)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(orphan).path))
    }

    /// Re-importing replaces a corrupt manifest, which is the documented recovery path.
    @Test func reimportRecoversFromCorruptManifest() async throws {
        let fixture = try AppTestFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        let storage = PetImageStorage(directory: fixture.directory)
        try Data("{ not json".utf8).write(to: storage.manifestURL)

        app.showSetupWizard()
        let load = Task { await app.loadSavedPetImage() }
        let sheet = try await waitForSheet(app)
        sheet.sheetParent?.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        await load.value
        #expect(app.imageLoadFailed)

        let replacement = try fixture.exampleImages()
        #expect(await app.confirmPetImage(replacement))

        #expect(!app.imageLoadFailed)
        let stored = try storage.readManifest()
        let manifest = try #require(stored)
        #expect(manifest.keys.sorted() == PetImageCategory.allCases.map(\.rawValue).sorted())
        #expect(try fixture.frameData().count == 9)
    }

    /// A failed migration commit keeps the legacy frames and blocks edits instead of losing them.
    @Test func failedMigrationCommitBlocksEditsAndKeepsFrames() async throws {
        let fixture = try AppTestFixture()
        defer { fixture.close() }
        let app = fixture.app
        let storage = PetImageStorage(directory: fixture.directory)
        let legacy = try storage.stage(fixture.exampleImages(), replacing: PetImageSet(), files: [:])
        app.settings.petImageFiles = legacy
        #expect(try storage.readManifest() == nil)
        app.showSetupWizard()
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: fixture.directory.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: fixture.directory.path) }

        let load = Task { await app.loadSavedPetImage() }
        let sheet = try await waitForSheet(app)
        sheet.sheetParent?.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        await load.value

        #expect(app.imageLoadFailed)
        #expect(app.imageLoadError is PetImageManifestError)
        #expect(try storage.readManifest() == nil)
        #expect(try fixture.frameData().count == 9)
    }
}
