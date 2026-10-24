import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct CharacterFrameEditorPreviewTests {
    @Test(arguments: [SpriteFrameEditingMode.sheet, .individualFrames])
    func canvasOnlyChangesReusePreviewImages(mode: SpriteFrameEditingMode) throws {
        let model = try preparedModel(mode: mode)
        let before = try #require(model.beforeImage(for: .idle1))
        let after = try #require(model.afterImage(for: .idle1))
        for step in 0 ..< 40 {
            model.setZoomScale(step.isMultiple(of: 2) ? 1.25 : 1)
            model.showsGrid.toggle()
            model.showsCrosshair.toggle()
            model.tool = step.isMultiple(of: 2) ? .align : .crop
            #expect(model.beforeImage(for: .idle1) === before)
            #expect(model.afterImage(for: .idle1) === after)
        }
        #expect(!model.needsStaging)
    }

    @Test(arguments: [SpriteFrameEditingMode.sheet, .individualFrames])
    func editsAndResetsRefreshOnlyTheAffectedPreview(mode: SpriteFrameEditingMode) throws {
        let model = try preparedModel(mode: mode)
        let before = try #require(model.beforeImage(for: .idle1))
        let initialAfter = try #require(model.afterImage(for: .idle1))
        model.setOffsetX(9)
        let shifted = try #require(model.afterImage(for: .idle1))
        #expect(shifted !== initialAfter)
        #expect(model.afterImage(for: .idle1) === shifted)
        #expect(model.beforeImage(for: .idle1) === before)
        try expectPixelsMatchRenderer(model, image: shifted, slot: .idle1)

        model.setCropSize(200)
        let cropped = try #require(model.afterImage(for: .idle1))
        #expect(cropped !== shifted)
        try expectPixelsMatchRenderer(model, image: cropped, slot: .idle1)
        model.resetCurrentFrame()
        let reset = try #require(model.afterImage(for: .idle1))
        #expect(reset !== cropped)
        try expectPixelsMatchRenderer(model, image: reset, slot: .idle1)

        model.setOffsetY(7)
        let shiftedAgain = try #require(model.afterImage(for: .idle1))
        model.resetAll()
        let resetAll = try #require(model.afterImage(for: .idle1))
        #expect(resetAll !== shiftedAgain)
        #expect(model.beforeImage(for: .idle1) === before)
        try expectPixelsMatchRenderer(model, image: resetAll, slot: .idle1)
    }

    @Test(arguments: [SpriteFrameEditingMode.sheet, .individualFrames])
    func previewsKeepOnlyTheLatestPairAndReleaseOnClose(mode: SpriteFrameEditingMode) throws {
        let model = try preparedModel(mode: mode)
        weak var before: NSImage?
        weak var after: NSImage?
        autoreleasepool {
            before = model.beforeImage(for: .idle1)
            after = model.afterImage(for: .idle1)
        }
        #expect(before != nil)
        #expect(after != nil)
        model.select(.idle2)
        try autoreleasepool {
            _ = try #require(model.beforeImage(for: .idle2))
            let next = try #require(model.afterImage(for: .idle2))
            try expectPixelsMatchRenderer(model, image: next, slot: .idle2)
        }
        #expect(before == nil)
        #expect(after == nil)
        autoreleasepool {
            before = model.beforeImage(for: .idle2)
            after = model.afterImage(for: .idle2)
        }
        #expect(before != nil)
        #expect(after != nil)
        model.releaseResources()
        #expect(before == nil)
        #expect(after == nil)
        #expect(model.beforeImage(for: .idle2) == nil)
        #expect(model.afterImage(for: .idle2) == nil)
        #expect(model.isReleased)
    }

    @Test func outputSizeChangesInvalidateThePreview() throws {
        let model = try preparedModel(mode: .sheet)
        let initial = try #require(model.afterImage(for: .idle1))
        var editing = try #require(model.editing)
        editing.cellSize /= 2
        model.editing = editing
        let resized = try #require(model.afterImage(for: .idle1))
        #expect(resized !== initial)
        #expect(resized.size.width == CGFloat(model.outputSide))
        try expectPixelsMatchRenderer(model, image: resized, slot: .idle1)
    }

    @Test func changedIndividualRasterInvalidatesBothPreviews() throws {
        let frames = try SetupWizardFixture.sheetImages()
        let model = try CharacterFrameEditorModel(frames: frames, localization: makeLocalization())
        let before = try #require(model.beforeImage(for: .idle1))
        let after = try #require(model.afterImage(for: .idle1))
        let replacement = try #require(PetFrameSourceDecoder.frameImage(from: frames[.typing][0]))
        let source = frames[.idle][0]
        for representation in source.representations {
            source.removeRepresentation(representation)
        }
        source.addRepresentation(NSBitmapImageRep(cgImage: replacement))
        let newBefore = try #require(model.beforeImage(for: .idle1))
        let newAfter = try #require(model.afterImage(for: .idle1))
        #expect(newBefore !== before)
        #expect(newAfter !== after)
        try expectPixelsMatchRenderer(model, image: newBefore, slot: .idle1)
        try expectPixelsMatchRenderer(model, image: newAfter, slot: .idle1)
    }

    private func preparedModel(mode: SpriteFrameEditingMode) throws -> CharacterFrameEditorModel {
        if mode == .sheet {
            return try makePreparedFrameEditorModel()
        }
        return try CharacterFrameEditorModel(
            frames: SetupWizardFixture.sheetImages(), localization: makeLocalization()
        )
    }

    /// Compare complete raster bytes with the unchanged renderer, not just object identity.
    private func expectPixelsMatchRenderer(
        _ model: CharacterFrameEditorModel, image: NSImage, slot: SpriteFrameSlot
    ) throws {
        let source = try #require(model.sourceImage(for: slot))
        let editing = try #require(model.editing)
        let expected = try #require(SpriteFrameRenderer.renderCanvas(
            source: source, adjustment: editing.adjustment(for: slot),
            canvasSide: model.canvasSide(for: slot), cappedOutputSide: CharacterFrameEditorModel.previewSide
        ))
        let actual = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(actual.width == expected.width)
        #expect(actual.height == expected.height)
        #expect(actual.bytesPerRow == expected.bytesPerRow)
        let actualData = try #require(actual.dataProvider?.data)
        let expectedData = try #require(expected.dataProvider?.data)
        #expect(actualData as Data == expectedData as Data)
    }
}
