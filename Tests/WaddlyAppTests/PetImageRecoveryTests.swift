import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// App-level recovery through the real alerts and setup sheet. The transaction-only recovery cases
/// live in `PetImageStoreTests`; these keep the paths that can only be exercised through the app.
@Suite(.serialized) @MainActor struct PetImageRecoveryTests {
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
        let storedManifest = try storage.readManifest()
        let manifest = try #require(storedManifest)
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
