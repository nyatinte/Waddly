import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Model-level regression coverage for the frame editor: crop-size centring, the fixed canvas
/// cap, restored navigator thumbnails and the legacy custom-layout gate.
@Suite(.serialized) @MainActor struct CharacterFrameEditorModelTests {
    /// Repeated 1 px slider/stepper changes must keep the crop centred instead of drifting half a
    /// pixel per step (integer division used to lose every half-pixel).
    @Test func repeatedCropSizeChangesKeepTheCropCentred() throws {
        let editor = try makePreparedFrameEditorModel()
        editor.select(.idle1)
        let initial = editor.currentAdjustment.crop
        for _ in 0 ..< 40 {
            editor.setCropSize(editor.currentAdjustment.crop.size - 1)
        }
        let resized = editor.currentAdjustment.crop
        #expect(resized.size == initial.size - 40)
        let initialCenter2 = 2 * initial.x + initial.size
        let resizedCenter2 = 2 * resized.x + resized.size
        #expect(abs(initialCenter2 - resizedCenter2) <= 1)
        #expect(resized.size <= editor.outputSide)
    }

    @Test func cropSizeIsCappedAtTheFixedOutputCanvas() throws {
        let editor = try makePreparedFrameEditorModel()
        editor.select(.idle1)
        editor.setCropSize(10000)
        #expect(editor.currentAdjustment.crop.size == editor.outputSide)
        editor.setCropSize(1)
        #expect(editor.currentAdjustment.crop.size == editor.minimumCropSide)
    }

    /// Restored pending edits must also update the navigator thumbnails, not just the badges and
    /// the After preview.
    @Test func reopenedEditsRefreshTheNavigatorThumbnail() async throws {
        let importModel = CharacterImportModel(
            currentImages: { PetImageSet() },
            commit: { _ in .committed }
        )
        try await importModel.stageFiles(at: [SetupWizardFixture.sheetURL()])
        let first = try CharacterFrameEditorModel(importModel: importModel, localization: makeLocalization())
        await first.prepare()
        first.select(.idle1)
        first.setOffsetX(9)
        first.setCropSize(200)
        #expect(await first.stageIntoDraft())

        let reopened = try CharacterFrameEditorModel(importModel: importModel, localization: makeLocalization())
        await reopened.prepare()
        #expect(reopened.editing?.isEdited(.idle1) == true)
        #expect(reopened.adjustedThumbnails[.idle1] != nil)
    }

    /// Older releases allowed custom frame counts. They must not fall into an editor that can only
    /// fail; the shared screen explains the re-import path instead.
    @Test func customLegacyFrameLayoutIsNotAdjustable() throws {
        var frames = try SetupWizardFixture.sheetImages()
        frames[.idle].append(frames[.typing][0])
        frames[.typing].removeFirst()
        frames[.typing].removeFirst()
        #expect(frames.isComplete)

        let model = CharacterImportModel(currentImages: { frames }, commit: { _ in .committed })
        model.reload()
        #expect(model.hasStagedCandidate)
        #expect(!model.canAdjustFrames)

        let plain = try SetupWizardFixture.sheetImages()
        let standard = CharacterImportModel(currentImages: { plain }, commit: { _ in .committed })
        standard.reload()
        #expect(standard.canAdjustFrames)
    }
}
