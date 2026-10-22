import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp
import WaddlyCore

/// The frame crop and alignment editor: the staged draft contract, the editor's own state machine,
/// and the persistence round trip that keeps a newly imported sheet editable after reopening.
@Suite(.serialized) @MainActor struct CharacterFrameEditorTests {
    // MARK: - Window lifecycle

    /// Closing releases the app's reference and detaches the hosted SwiftUI view. Reopening builds a
    /// fresh model on the pet that is committed now.
    @Test func releaseOnCloseAndRebuildOnReopen() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.showChangeCharacter()
        let window = try #require(app.characterImportWindowController?.window)
        #expect(window.contentView?.subviews.contains { $0 is NSHostingView<CharacterImportView> } == true)
        let first = try #require(app.characterImportWindowController)

        window.close()
        #expect(app.characterImportWindowController == nil)
        #expect(window.contentView == nil)

        app.showChangeCharacter()
        let second = try #require(app.characterImportWindowController)
        #expect(second !== first)
    }

    @Test func aMiniaturizedWindowDoesNotReloadItsDraftOnRefocus() {
        #expect(!CharacterImportWindowController.shouldReloadDraft(isVisible: false, isMiniaturized: true))
        #expect(!CharacterImportWindowController.shouldReloadDraft(isVisible: true, isMiniaturized: false))
        #expect(CharacterImportWindowController.shouldReloadDraft(isVisible: false, isMiniaturized: false))
    }

    @Test func duplicateWindowApplyCannotCloseWhileTheCommitIsSuspendedOrFails() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let gate = CharacterImportCommitGate()
        let app = fixture.app
        let gatedModel = CharacterImportModel(
            currentImages: { app.petImages },
            commit: { _ in await gate.commit() }
        )
        let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
        let localization = LocalizationController(settings: app.settings, resources: resources)
        let gatedController = CharacterImportWindowController(
            model: gatedModel,
            localization: localization,
            presenter: .invisible,
            onClose: {}
        )
        gatedController.focus()
        let window = try #require(gatedController.window)
        await gatedModel.stageFiles(at: [fixture.exampleURL])
        let firstApply = gatedController.applyAndClose()
        #expect(await gate.waitUntilEntered())
        #expect(!gatedController.windowShouldClose(window))
        let duplicateApply = gatedController.applyAndClose()
        await duplicateApply.value
        #expect(window.isVisible)
        #expect(gatedModel.isApplying)
        #expect(gate.commitCount == 1)
        gate.resume(with: .failed)
        await firstApply.value
        #expect(gatedModel.commitFailed)
        #expect(window.isVisible)
        #expect(gatedModel.canApply)
        gatedModel.discard()
        gatedController.close()
    }

    @Test func applyingThroughTheStoreWritesThePetAndReopenShowsIt() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        app.showChangeCharacter()
        let controller = try #require(app.characterImportWindowController)
        await controller.model.stageFiles(at: [fixture.exampleURL])
        let staged = try #require(controller.model.stagedFrames)

        await controller.model.apply()

        #expect(!controller.model.commitFailed)
        #expect(app.petImages[.idle].first === staged[.idle].first)
        let manifest = try #require(try fixture.manifest())
        #expect(manifest == app.settings.petImageFiles)
        let diskLoaded = try PetImageStorage(directory: fixture.directory).load(manifest).0
        #expect(diskLoaded.isComplete)
        #expect(!controller.model.isDirty)

        controller.close()
        #expect(app.characterImportWindowController == nil)
        app.importedImages = nil
        await app.loadSavedPetImage()
        #expect(app.petImages.isComplete)
        #expect(try fixture.manifest() == manifest)
        for category in PetImageCategory.allCases {
            #expect(app.petImages[category].count == (manifest[category.rawValue]?.count ?? 0))
        }

        app.showChangeCharacter()
        let reopened = try #require(app.characterImportWindowController)
        let reopenedFrames = try #require(reopened.model.stagedFrames)
        #expect(CharacterImportModel.sameFrames(reopenedFrames, app.petImages))
        #expect(!reopened.model.isDirty)
        #expect(CharacterImportModel.sameFrames(reopened.model.committedBaseline, app.petImages))
    }

    // MARK: - Staged draft semantics

    /// Done hands the nine adjusted frames back to the parent draft and nothing is written until the
    /// parent Apply. The original sheet and edit parameters survive the round trip.
    @Test func doneStagesAdjustedFramesAndApplyPersistsThem() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        let committedBefore = app.petImages
        app.showChangeCharacter()
        let controller = try #require(app.characterImportWindowController)
        await controller.model.stageFiles(at: [fixture.exampleURL])
        let localization = try makeLocalization()
        let editor = CharacterFrameEditorModel(importModel: controller.model, localization: localization)
        await editor.prepare()
        #expect(editor.isSheetMode)

        editor.select(.idle1)
        editor.setCropSize(200)
        editor.setOffsetX(7)
        editor.select(.typing2)
        editor.nudge(deltaX: 0, deltaY: -3)
        let expectedIdle = try #require(editor.editing?.adjustment(for: .idle1))
        let expectedTyping = try #require(editor.editing?.adjustment(for: .typing2))

        #expect(await editor.stageIntoDraft())

        let staged = try #require(controller.model.stagedFrames)
        #expect(controller.model.isDirty)
        #expect(CharacterImportModel.sameFrames(committedBefore, app.petImages))
        #expect(staged.editingSource?.editing.adjustment(for: .idle1) == expectedIdle)
        #expect(staged.editingSource?.editing.adjustment(for: .typing2) == expectedTyping)
        #expect(staged.editingSource?.sheetPNGData != nil)
        #expect(try fixture.manifest() == app.settings.petImageFiles)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.directory.appendingPathComponent("source-sheet.png").path
        ))

        await controller.model.apply()
        let persistedDirectory = fixture.directory.appendingPathComponent("source-sheet.png")
        #expect(FileManager.default.fileExists(atPath: persistedDirectory.path))
        #expect(FileManager.default.fileExists(
            atPath: fixture.directory.appendingPathComponent("frame-edits.json").path
        ))
        let committed = app.petImages
        // The crop narrows the visible window inside the fixed cell-sized canvas; it must not
        // rescale the character or change the exported frame dimensions.
        #expect(committed[.idle][0].size.width == 256)
        #expect(committed[.typing][1].size.width == 256)
        #expect(committed[.typing][0].size.width == 256)
        #expect(app.petImages.editingSource?.editing.adjustment(for: .idle1).crop.size == 200)

        controller.close()
        app.importedImages = nil
        await app.loadSavedPetImage()
        #expect(app.petImages.editingSource?.editing.adjustment(for: .idle1) == expectedIdle)
        let restored = try #require(app.petImages.editingSource)
        #expect(restored.sheetPNGData != nil)
    }

    /// Done without changes must not replace the draft's frame objects, while Reset all after a
    /// previously staged edit must restore the exact-thirds extraction on the draft.
    @Test func untouchedEditorDoesNotDirtyTheDraftAndResetAllDoes() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.showChangeCharacter()
        let controller = try #require(app.characterImportWindowController)
        await controller.model.stageFiles(at: [fixture.exampleURL])
        let stagedBefore = try #require(controller.model.stagedFrames)
        let idleImage = try #require(stagedBefore[.idle].first)

        let untouched = try CharacterFrameEditorModel(
            importModel: controller.model,
            localization: makeLocalization()
        )
        await untouched.prepare()
        #expect(!untouched.needsStaging)

        untouched.select(.idle1)
        untouched.setCropSize(200)
        #expect(untouched.needsStaging)
        #expect(await untouched.stageIntoDraft())
        #expect(controller.model.stagedFrames?[.idle].first !== idleImage)
        #expect(controller.model.stagedFrames?.editingSource?.editing.adjustment(for: .idle1).crop.size == 200)

        let reopened = try CharacterFrameEditorModel(
            importModel: controller.model,
            localization: makeLocalization()
        )
        await reopened.prepare()
        #expect(
            !reopened.needsStaging
                || reopened.editing?.adjustments == reopened.sourceFrames.editingSource?.editing.adjustments
        )
        reopened.resetAll()
        #expect(reopened.needsStaging)
        #expect(await reopened.stageIntoDraft())
        let reset = try #require(controller.model.stagedFrames)
        #expect(reset.editingSource?.editing.hasEdits == false)
        #expect(reset[.idle][0].size.width == 256)
        #expect(reset[.typing][2].size.width == 256)
    }

    /// A legacy pet only has its nine saved frames. It must stay editable frame by frame, and the
    /// editor must explain that the original sheet is unavailable rather than inventing one.
    @Test func legacySavedFramesUsePerFrameEditing() async throws {
        let frames = try SetupWizardFixture.sheetImages()
        let model = CharacterImportModel(currentImages: { frames }, commit: { _ in .committed })
        model.reload()
        let editor = try CharacterFrameEditorModel(importModel: model, localization: makeLocalization())
        await editor.prepare()

        #expect(!editor.isSheetMode)
        #expect(editor.editing?.mode == .individualFrames)
        editor.select(.sleep1)
        editor.setCropSize(200)
        editor.setOffsetY(4)
        #expect(await editor.stageIntoDraft())

        let staged = try #require(model.stagedFrames)
        #expect(staged[.sleep][0].size.width == 256)
        #expect(staged.editingSource == nil)
        #expect(model.isDirty)
    }

    /// Cancel and discard leave the committed pet untouched; staging never writes.
    @Test func discardKeepsTheCommittedPet() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        let original = app.petImages
        let originalManifest = try fixture.manifest()
        app.showChangeCharacter()
        let controller = try #require(app.characterImportWindowController)
        await controller.model.stageFiles(at: [fixture.exampleURL])
        let editor = try CharacterFrameEditorModel(importModel: controller.model, localization: makeLocalization())
        await editor.prepare()
        editor.setCropSize(180)
        #expect(await editor.stageIntoDraft())
        #expect(controller.model.isDirty)

        controller.model.discard()

        #expect(CharacterImportModel.sameFrames(app.petImages, original))
        #expect(try fixture.manifest() == originalManifest)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.directory.appendingPathComponent("source-sheet.png").path
        ))
    }

    // MARK: - Localization and sizing

    @Test func everyEditorLayoutFitsTheDocumentedWindowSizes() {
        #expect(FrameEditorMetrics.preferredSize.width >= 1180)
        #expect(FrameEditorMetrics.preferredSize.width <= 1320)
        #expect(FrameEditorMetrics.preferredSize.height >= 740)
        #expect(FrameEditorMetrics.preferredSize.height <= 840)
        #expect(FrameEditorMetrics.minimumSize.width >= 1000)
        #expect(FrameEditorMetrics.minimumSize.height >= 660)
    }

    @Test func editorStringsExistInBothLanguages() throws {
        let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
        for language in [AppLanguage.english, .japanese] {
            let name = "WaddlyTests.frameEditorLocale.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let settings = try AppSettings(defaults: defaults)
            settings.appLanguage = language
            let localization = LocalizationController(settings: settings, resources: resources)
            for key: LocalizationKey in [
                .characterAdjustFrames,
                .frameEditorWindowTitle,
                .frameEditorDone,
                .frameEditorResetAll,
                .frameEditorFrames,
                .frameEditorInspectorTitle,
                .frameEditorToolCrop,
                .frameEditorToolAlign,
                .frameEditorGuideGrid,
                .frameEditorGuideCrosshair,
                .frameEditorLegacyNotice
            ] {
                #expect(localization.string(for: key) != key.rawValue)
            }
        }
    }
}

// MARK: - Helpers

@MainActor
func makeLocalization(
    language: AppLanguage = .english
) throws -> LocalizationController {
    let name = "WaddlyTests.frameEditor.\(UUID().uuidString)"
    let settings = try AppSettings(defaults: #require(UserDefaults(suiteName: name)))
    settings.appLanguage = language
    let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
    return LocalizationController(settings: settings, resources: resources)
}

/// A prepared editor model over the example sheet, for model-level tests and captures.
@MainActor
func makePreparedFrameEditorModel(
    language: AppLanguage = .english
) throws -> CharacterFrameEditorModel {
    let data = try Data(contentsOf: SetupWizardFixture.sheetURL())
    let candidate = try #require(try PetSpriteSheetImporter.inspect(data).get())
    let sheet = try #require(PetFrameSourceDecoder.sheetImage(from: candidate.sheetPNGData))
    return try CharacterFrameEditorModel(
        frames: candidate.images,
        localization: makeLocalization(language: language),
        sheet: sheet
    )
}
