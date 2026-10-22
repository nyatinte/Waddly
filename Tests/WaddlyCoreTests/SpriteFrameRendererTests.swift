import AppKit
import Testing
import WaddlyCore

// MARK: - Fixed-canvas renderer

@Test func canvasRendererRendersEachNominalCellColor() throws {
    let sheet = try #require(spriteTestSolidSheet())
    let editing = spriteTestSheetEditing()
    for slot in SpriteFrameSlot.allCases {
        let rendered = try #require(SpriteFrameRenderer.renderCanvas(
            source: sheet,
            adjustment: editing.adjustment(for: slot),
            canvasSide: 60
        ))
        #expect(rendered.width == 60)
        #expect(rendered.height == 60)
        #expect(spriteTestPixel(of: rendered, column: 30, row: 30) == spriteTestCellColors[slot.rawValue])
    }
}

@Test func canvasRendererIsUprightInTopLeftCoordinates() throws {
    let sheet = try #require(spriteTestOrientedSheet())
    let editing = spriteTestSheetEditing()
    for slot in SpriteFrameSlot.allCases {
        let rendered = try #require(SpriteFrameRenderer.renderCanvas(
            source: sheet,
            adjustment: editing.adjustment(for: slot),
            canvasSide: 60
        ))
        let expected = spriteTestCellColors[slot.rawValue]
        // The crop's top half is the cell color and its bottom half is inverted; a flipped render
        // would swap those rows.
        #expect(spriteTestPixel(of: rendered, column: 30, row: 20) == expected)
        #expect(spriteTestPixel(of: rendered, column: 30, row: 29) == expected)
        #expect(spriteTestPixel(of: rendered, column: 30, row: 30) == expected.inverted)
        #expect(spriteTestPixel(of: rendered, column: 30, row: 39) == expected.inverted)
    }
}

@Test func canvasRendererAlwaysOutputsCanvasSideSquare() throws {
    let sheet = try #require(spriteTestSolidSheet())
    let small = FrameAdjustment(crop: SquareCrop(x: 20, y: 20, size: 10), offsetX: 0, offsetY: 0)
    let large = FrameAdjustment(crop: SquareCrop(x: 0, y: 0, size: 60), offsetX: 0, offsetY: 0)
    for adjustment in [small, large] {
        let rendered = try #require(
            SpriteFrameRenderer.renderCanvas(source: sheet, adjustment: adjustment, canvasSide: 60)
        )
        #expect(rendered.width == 60)
        #expect(rendered.height == 60)
    }
    let smallCanvas = try #require(
        SpriteFrameRenderer.renderCanvas(source: sheet, adjustment: large, canvasSide: 24)
    )
    #expect(smallCanvas.width == 24)
    #expect(smallCanvas.height == 24)
    #expect(SpriteFrameRenderer.renderCanvas(source: sheet, adjustment: small, canvasSide: 0) == nil)
    let empty = FrameAdjustment(crop: SquareCrop(x: 0, y: 0, size: 0), offsetX: 0, offsetY: 0)
    #expect(SpriteFrameRenderer.renderCanvas(source: sheet, adjustment: empty, canvasSide: 60) == nil)
}

@Test func canvasRendererCentersTheCropWithoutScaling() throws {
    let sheet = try #require(spriteTestOrientedSheet())
    let adjustment = FrameAdjustment(crop: SquareCrop(x: 20, y: 20, size: 20), offsetX: 0, offsetY: 0)
    let rendered = try #require(
        SpriteFrameRenderer.renderCanvas(source: sheet, adjustment: adjustment, canvasSide: 60)
    )
    let color = spriteTestCellColors[4]
    // 20 px of content centred in the 60 px canvas: columns and rows 20...39, transparent elsewhere.
    #expect(spriteTestPixel(of: rendered, column: 19, row: 19) == .clear)
    #expect(spriteTestPixel(of: rendered, column: 20, row: 19) == .clear)
    #expect(spriteTestPixel(of: rendered, column: 40, row: 20) == .clear)
    #expect(spriteTestPixel(of: rendered, column: 39, row: 40) == .clear)
    #expect(spriteTestPixel(of: rendered, column: 20, row: 20) == color)
    #expect(spriteTestPixel(of: rendered, column: 39, row: 20) == color)
    #expect(spriteTestPixel(of: rendered, column: 20, row: 29) == color)
    #expect(spriteTestPixel(of: rendered, column: 20, row: 30) == color.inverted)
    #expect(spriteTestPixel(of: rendered, column: 39, row: 39) == color.inverted)
}

@Test func canvasRendererCenteredSizeChangeKeepsPixelsInPlace() throws {
    let sheet = try #require(spriteTestOrientedSheet())
    let big = FrameAdjustment(crop: SquareCrop(x: 20, y: 20, size: 20), offsetX: 0, offsetY: 0)
    let small = FrameAdjustment(crop: SquareCrop(x: 25, y: 25, size: 10), offsetX: 0, offsetY: 0)
    let bigCanvas = try #require(
        SpriteFrameRenderer.renderCanvas(source: sheet, adjustment: big, canvasSide: 60)
    )
    let smallCanvas = try #require(
        SpriteFrameRenderer.renderCanvas(source: sheet, adjustment: small, canvasSide: 60)
    )
    // Both crops are centred, so the shared 10x10 window shows the same source pixels in place.
    for row in 25 ... 34 {
        for column in 25 ... 34 {
            #expect(spriteTestPixel(of: bigCanvas, column: column, row: row)
                == spriteTestPixel(of: smallCanvas, column: column, row: row))
        }
    }
    // The smaller crop only adds transparent padding around the same window; content stays unscaled.
    #expect(spriteTestPixel(of: smallCanvas, column: 24, row: 25) == .clear)
    #expect(spriteTestPixel(of: smallCanvas, column: 35, row: 25) == .clear)
    #expect(spriteTestPixel(of: smallCanvas, column: 25, row: 24) == .clear)
    #expect(spriteTestPixel(of: smallCanvas, column: 25, row: 35) == .clear)
}

@Test func canvasRendererOffsetPadsAndClips() throws {
    let sheet = try #require(spriteTestSolidSheet())
    let crop = SquareCrop(x: 20, y: 20, size: 20)
    let color = spriteTestCellColors[4]
    let shifted = try #require(SpriteFrameRenderer.renderCanvas(
        source: sheet,
        adjustment: FrameAdjustment(crop: crop, offsetX: 10, offsetY: -15),
        canvasSide: 60
    ))
    // Content origin: (30 - 10 + 10, 30 - 10 - 15) = (30, 5), so columns 30...49 and rows 5...24.
    #expect(spriteTestPixel(of: shifted, column: 29, row: 10) == .clear)
    #expect(spriteTestPixel(of: shifted, column: 30, row: 5) == color)
    #expect(spriteTestPixel(of: shifted, column: 49, row: 24) == color)
    #expect(spriteTestPixel(of: shifted, column: 50, row: 10) == .clear)
    #expect(spriteTestPixel(of: shifted, column: 30, row: 4) == .clear)
    #expect(spriteTestPixel(of: shifted, column: 30, row: 25) == .clear)
    let clipped = try #require(SpriteFrameRenderer.renderCanvas(
        source: sheet,
        adjustment: FrameAdjustment(crop: crop, offsetX: 40, offsetY: 0),
        canvasSide: 60
    ))
    // Content origin x = 30 - 10 + 40 = 60: the whole crop is clipped off the right edge.
    #expect(spriteTestPixel(of: clipped, column: 59, row: 30) == .clear)
}

@Test func canvasRendererCropLargerThanCanvasClipsAndKeepsNeighbors() throws {
    let sheet = try #require(spriteTestSolidSheet())
    let rendered = try #require(SpriteFrameRenderer.renderCanvas(
        source: sheet,
        adjustment: FrameAdjustment(crop: SquareCrop(x: 10, y: 10, size: 40), offsetX: 0, offsetY: 0),
        canvasSide: 60
    ))
    // Content origin: 30 - 20 = 10, so canvas (column, row) samples source (column, row) for 10...49.
    #expect(spriteTestPixel(of: rendered, column: 10, row: 10) == spriteTestCellColors[0])
    #expect(spriteTestPixel(of: rendered, column: 30, row: 10) == spriteTestCellColors[1])
    #expect(spriteTestPixel(of: rendered, column: 10, row: 30) == spriteTestCellColors[3])
    #expect(spriteTestPixel(of: rendered, column: 30, row: 30) == spriteTestCellColors[4])
    #expect(spriteTestPixel(of: rendered, column: 9, row: 9) == .clear)
    #expect(spriteTestPixel(of: rendered, column: 50, row: 50) == .clear)

    let clipped = try #require(SpriteFrameRenderer.renderCanvas(
        source: sheet,
        adjustment: FrameAdjustment(crop: SquareCrop(x: 10, y: 10, size: 60), offsetX: 0, offsetY: 0),
        canvasSide: 40
    ))
    // Content origin: 20 - 30 = -10, so canvas (0, 0) samples source (20, 20).
    #expect(clipped.width == 40)
    #expect(clipped.height == 40)
    #expect(spriteTestPixel(of: clipped, column: 0, row: 0) == spriteTestCellColors[4])
    #expect(spriteTestPixel(of: clipped, column: 39, row: 39) == spriteTestCellColors[8])
}

@Test func canvasRendererCropOriginPansContent() throws {
    let sheet = try #require(spriteTestSolidSheet())
    let leftCrop = FrameAdjustment(crop: SquareCrop(x: 20, y: 20, size: 20), offsetX: 0, offsetY: 0)
    let rightCrop = FrameAdjustment(crop: SquareCrop(x: 40, y: 20, size: 20), offsetX: 0, offsetY: 0)
    let left = try #require(SpriteFrameRenderer.renderCanvas(source: sheet, adjustment: leftCrop, canvasSide: 60))
    let right = try #require(SpriteFrameRenderer.renderCanvas(source: sheet, adjustment: rightCrop, canvasSide: 60))
    #expect(spriteTestPixel(of: left, column: 20, row: 20) == spriteTestCellColors[4])
    #expect(spriteTestPixel(of: right, column: 20, row: 20) == spriteTestCellColors[5])
    #expect(spriteTestPixel(of: left, column: 35, row: 35) == spriteTestCellColors[4])
    #expect(spriteTestPixel(of: right, column: 35, row: 35) == spriteTestCellColors[5])
}

@Test func canvasRendererCappedOutputScalesAndKeepsChannels() throws {
    let sheet = try #require(spriteTestOrientedSheet())
    let adjustment = FrameAdjustment(crop: SquareCrop(x: 20, y: 20, size: 20), offsetX: 0, offsetY: 0)
    let capped = try #require(SpriteFrameRenderer.renderCanvas(
        source: sheet, adjustment: adjustment, canvasSide: 60, cappedOutputSide: 30
    ))
    #expect(capped.width == 30)
    #expect(capped.height == 30)
    // Content is scaled by 0.5: a 10x10 window at columns and rows 10...19.
    #expect(spriteTestPixel(of: capped, column: 9, row: 9) == .clear)
    #expect(spriteTestPixel(of: capped, column: 10, row: 10) == spriteTestCellColors[4])
    #expect(spriteTestPixel(of: capped, column: 19, row: 19) == spriteTestCellColors[4].inverted)
    #expect(spriteTestPixel(of: capped, column: 20, row: 20) == .clear)

    let solid = try #require(spriteTestSolidSheet())
    let spanning = FrameAdjustment(crop: SquareCrop(x: 30, y: 20, size: 20), offsetX: 0, offsetY: 0)
    let scaledSpan = try #require(SpriteFrameRenderer.renderCanvas(
        source: solid, adjustment: spanning, canvasSide: 60, cappedOutputSide: 30
    ))
    #expect(spriteTestPixel(of: scaledSpan, column: 10, row: 15) == spriteTestCellColors[4])
    #expect(spriteTestPixel(of: scaledSpan, column: 19, row: 15) == spriteTestCellColors[5])

    let natural = try #require(SpriteFrameRenderer.renderCanvas(
        source: sheet, adjustment: adjustment, canvasSide: 60, cappedOutputSide: 90
    ))
    #expect(natural.width == 60)
    #expect(natural.height == 60)
    let image = try #require(SpriteFrameRenderer.renderCanvasNSImage(
        source: sheet, adjustment: adjustment, canvasSide: 60, cappedOutputSide: 30
    ))
    #expect(image.size == NSSize(width: 30, height: 30))
    let naturalImage = try #require(SpriteFrameRenderer.renderCanvasNSImage(
        source: sheet, adjustment: adjustment, canvasSide: 60
    ))
    #expect(naturalImage.size == NSSize(width: 60, height: 60))
    #expect(SpriteFrameRenderer.renderCanvasNSImage(
        source: sheet, adjustment: adjustment, canvasSide: -1
    ) == nil)
}

@Test func canvasRendererPreservesAlphaAndChannels() throws {
    let translucent = SpriteTestPixel(red: 64, green: 32, blue: 16, alpha: 128)
    let sheet = try #require(spriteTestImage(width: 60, height: 60) { column, row in
        guard column >= 40, row >= 40 else { return .clear }
        return translucent
    })
    let rendered = try #require(SpriteFrameRenderer.renderCanvas(
        source: sheet,
        adjustment: FrameAdjustment(crop: SquareCrop(x: 40, y: 40, size: 20), offsetX: 0, offsetY: 0),
        canvasSide: 60
    ))
    #expect(spriteTestPixel(of: rendered, column: 20, row: 20) == translucent)
    #expect(spriteTestPixel(of: rendered, column: 30, row: 30) == translucent)
    #expect(spriteTestPixel(of: rendered, column: 19, row: 30) == .clear)
    let empty = try #require(SpriteFrameRenderer.renderCanvas(
        source: sheet,
        adjustment: FrameAdjustment(crop: SquareCrop(x: 0, y: 0, size: 20), offsetX: 0, offsetY: 0),
        canvasSide: 60
    ))
    #expect(spriteTestPixel(of: empty, column: 30, row: 30) == .clear)
}

@Test func frameSourceDecoderDecodesTheSheetPNGAtFullSize() throws {
    let image = try #require(spriteTestSolidSheet())
    let data = try #require(spriteTestPNGData(for: image))
    let decoded = try #require(PetFrameSourceDecoder.sheetImage(from: data))
    #expect(decoded.width == 60)
    #expect(decoded.height == 60)
    #expect(spriteTestPixel(of: decoded, column: 5, row: 5) == spriteTestCellColors[0])
    #expect(spriteTestPixel(of: decoded, column: 55, row: 55) == spriteTestCellColors[8])
    #expect(PetFrameSourceDecoder.sheetImage(from: Data()) == nil)
    #expect(PetFrameSourceDecoder.sheetImage(from: Data("not a PNG".utf8)) == nil)
}

@Test func canvasHandleResizeKeepsSurvivingPixelsInPlace() throws {
    let sheet = try #require(spriteTestSolidSheet())
    let editing = spriteTestSheetEditing()
    let slot = SpriteFrameSlot.typing1
    let geometry = editing.geometry(for: slot)
    let baseline = editing.adjustment(for: slot)
    let color = spriteTestCellColors[slot.rawValue]
    let before = try #require(SpriteFrameRenderer.renderCanvas(
        source: sheet,
        adjustment: baseline,
        canvasSide: 60
    ))
    #expect(spriteTestPixel(of: before, column: 30, row: 30) == color)

    for delta in [-5, 5] {
        let resizedCrop = geometry.resized(
            baseline.crop,
            handle: .right,
            deltaX: delta,
            deltaY: 0
        )
        let resized = FrameAdjustment(crop: resizedCrop, offsetX: 0, offsetY: 0)
        let after = try #require(SpriteFrameRenderer.renderCanvas(
            source: sheet,
            adjustment: resized,
            canvasSide: 60
        ))
        // Centre-anchored handle resize only changes the mask: the surviving source pixels stay at
        // the same output coordinates instead of sliding by half the size delta.
        #expect(spriteTestPixel(of: after, column: 30, row: 30) == color)
        #expect(after.width == 60)
        #expect(after.height == 60)
    }
}
