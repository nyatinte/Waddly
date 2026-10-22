import AppKit
import SwiftUI
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

    /// Closing the editor must release the decoded sheet (the largest allocation) and the
    /// thumbnail caches with the model; nothing else should keep them alive.
    @Test func editorModelReleasesTheDecodedSheetAndThumbnails() throws {
        let localization = try makeLocalization()
        let candidate = try SetupWizardFixture.sheetCandidate()
        var sheet: CGImage? = try #require(PetFrameSourceDecoder.sheetImage(from: candidate.sheetPNGData))
        weak var weakModel: CharacterFrameEditorModel?
        weak var weakSheet: CGImage?

        autoreleasepool {
            let model = CharacterFrameEditorModel(
                frames: candidate.images,
                localization: localization,
                sheet: sheet
            )
            weakModel = model
            weakSheet = model.sheet
        }
        sheet = nil

        #expect(weakModel == nil)
        #expect(weakSheet == nil)
    }

    /// The editor releases the decoded sheet and thumbnail caches deterministically when its
    /// surface disappears, without waiting for the observable object itself to deallocate.
    @Test func closingTheEditorReleasesHeavyResources() throws {
        let localization = try makeLocalization()
        let candidate = try SetupWizardFixture.sheetCandidate()
        var sheet: CGImage? = try #require(PetFrameSourceDecoder.sheetImage(from: candidate.sheetPNGData))
        let model = CharacterFrameEditorModel(
            frames: candidate.images,
            localization: localization,
            sheet: sheet
        )
        weak var weakSheet: CGImage? = model.sheet
        #expect(model.sheet != nil)
        #expect(!model.baseThumbnails.isEmpty)

        model.releaseResources()

        #expect(model.sheet == nil)
        #expect(model.baseThumbnails.isEmpty)
        #expect(model.adjustedThumbnails.isEmpty)
        #expect(!model.sourceFrames.isComplete)
        sheet = nil
        #expect(weakSheet == nil)
        #expect(model.isReleased)
    }

    /// A released model must not decode the sheet again through a late `.task`.
    @Test func releasedModelIgnoresALatePrepare() async throws {
        let editor = try makePreparedFrameEditorModel()
        editor.releaseResources()
        await editor.prepare()
        #expect(editor.sheet == nil)
        #expect(editor.isReleased)
    }

    /// The canvas view keeps a strong reference to the decoded sheet while visible; dismantling it
    /// must drop that reference even if the view object itself is cached for a moment.
    @Test func canvasReleaseDropsTheDecodedSheet() throws {
        let candidate = try SetupWizardFixture.sheetCandidate()
        var sheet: CGImage? = try #require(PetFrameSourceDecoder.sheetImage(from: candidate.sheetPNGData))
        weak var weakSheet: CGImage? = sheet
        let canvas = FrameCanvasNSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        canvas.apply(FrameCanvasConfiguration(
            source: sheet,
            sourceSide: candidate.cellSize * 3,
            nominalCell: SquareCrop(x: 0, y: 0, size: candidate.cellSize),
            adjustment: FrameAdjustment(
                crop: SquareCrop(x: 0, y: 0, size: candidate.cellSize),
                offsetX: 0,
                offsetY: 0
            ),
            tool: .crop,
            zoomPercent: 100,
            showsGrid: true,
            showsCrosshair: true,
            showsWarning: false
        ))
        #expect(canvas.configuration != nil)
        canvas.releaseResources()
        #expect(canvas.configuration == nil)
        sheet = nil
        #expect(weakSheet == nil)
    }

    /// Even if a future host opened the editor for a custom frame layout, it must not compose or
    /// stage a truncated nine-frame draft over the user's saved frames.
    @Test func unsupportedLegacyLayoutCannotStageATruncatedDraft() async throws {
        var frames = try SetupWizardFixture.sheetImages()
        frames[.idle].append(frames[.typing][0])
        frames[.typing].removeFirst()
        frames[.typing].removeFirst()
        let importModel = CharacterImportModel(
            currentImages: { frames },
            commit: { _ in .committed }
        )
        importModel.reload()
        let before = try #require(importModel.stagedFrames)
        let editor = try CharacterFrameEditorModel(
            importModel: importModel,
            localization: makeLocalization()
        )
        await editor.prepare()

        #expect(editor.editing == nil)
        #expect(editor.composeFailed)
        #expect(await !editor.stageIntoDraft())
        #expect(try CharacterImportModel.sameFrames(#require(importModel.stagedFrames), before))
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
