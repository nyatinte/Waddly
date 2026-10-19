import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp
import WaddlyCore

/// The advanced per-frame editor surface: the Change Character window's lifecycle, the fixed content
/// minimum, and that advanced edits land in the staged draft rather than the committed pet.
@Suite(.serialized) @MainActor struct AnimationSettingsTests {
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

    /// The editor's minimum must be a *content* minimum that fits all four fixed rows plus the
    /// instructions. The old frame-based `minSize` subtracted the title bar and clipped the last row.
    @Test func minimumContentFitsAllFourRows() {
        let minimum = AnimationSettingsMetrics.contentMinSize
        let rows = AnimationSettingsMetrics.rowHeight * CGFloat(PetImageCategory.allCases.count)
        let gaps = AnimationSettingsMetrics.rowSpacing * CGFloat(PetImageCategory.allCases.count + 1)
        #expect(minimum.height >= rows + gaps
            + AnimationSettingsMetrics.instructionBlockHeight + AnimationSettingsMetrics.contentInset * 2)
        // 640 was the old frame height, which left the content shorter than four rows.
        #expect(minimum.height > 640)
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

    /// An advanced edit is staged, not committed: it reaches the change flow's own draft and leaves
    /// the saved pet untouched until Apply.
    @Test func advancedEditorStagesFramesWithoutCommitting() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.showChangeCharacter()
        let controller = try #require(app.characterImportWindowController)
        await controller.model.stageFiles(at: [fixture.exampleURL])
        let stagedIdleBefore = try #require(controller.model.stagedFrames)[.idle].count
        let committedIdleBefore = app.petImages[.idle].count
        let frame = try #require(app.petImages[.idle].first)
        let pngURL = fixture.directory.appendingPathComponent("staged.png")
        try #require(PetSpriteSheetImporter.pngData(for: frame)).write(to: pngURL)

        controller.frameEditorModel.drop([pngURL], on: .idle)

        #expect(await waitForStagedIdle(controller.model, count: stagedIdleBefore + 1))
        #expect(app.petImages[.idle].count == committedIdleBefore)
    }

    /// Apply through the real store: the pet is written to disk, and reopening loads the committed
    /// pet with no stale draft.
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
        #expect(manifest[PetImageCategory.idle.rawValue]?.isEmpty == false)
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
}

private extension AnimationSettingsTests {
    /// The advanced editor's add decodes on a detached task, so poll until the draft updates.
    func waitForStagedIdle(_ model: CharacterImportModel, count: Int) async -> Bool {
        for _ in 0 ..< 300 {
            if model.stagedFrames?[.idle].count == count {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
