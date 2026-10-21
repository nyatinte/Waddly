import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
import WaddlyCore

// MARK: - Renderer

@Test func rendererRendersEachNominalCellColor() throws {
    let sheet = try #require(spriteTestSolidSheet())
    let editing = spriteTestSheetEditing()
    for slot in SpriteFrameSlot.allCases {
        let rendered = try #require(
            SpriteFrameRenderer.render(source: sheet, adjustment: editing.adjustment(for: slot))
        )
        #expect(rendered.width == 20)
        #expect(rendered.height == 20)
        let expected = spriteTestCellColors[slot.rawValue]
        #expect(spriteTestPixel(of: rendered, column: 0, row: 0) == expected)
        #expect(spriteTestPixel(of: rendered, column: 19, row: 0) == expected)
        #expect(spriteTestPixel(of: rendered, column: 0, row: 19) == expected)
        #expect(spriteTestPixel(of: rendered, column: 19, row: 19) == expected)
    }
}

@Test func rendererIsUprightInTopLeftCoordinates() throws {
    let sheet = try #require(spriteTestOrientedSheet())
    let editing = spriteTestSheetEditing()
    for slot in SpriteFrameSlot.allCases {
        let rendered = try #require(
            SpriteFrameRenderer.render(source: sheet, adjustment: editing.adjustment(for: slot))
        )
        let expected = spriteTestCellColors[slot.rawValue]
        #expect(spriteTestPixel(of: rendered, column: 10, row: 0) == expected)
        #expect(spriteTestPixel(of: rendered, column: 10, row: 9) == expected)
        #expect(spriteTestPixel(of: rendered, column: 10, row: 10) == expected.inverted)
        #expect(spriteTestPixel(of: rendered, column: 10, row: 19) == expected.inverted)
    }
}

@Test func rendererOffsetPadsTransparentAndClips() throws {
    let sheet = try #require(spriteTestSolidSheet())
    let color = spriteTestCellColors[SpriteFrameSlot.enter.rawValue]
    let crop = SquareCrop(x: 0, y: 40, size: 20)
    let shiftedRight = try #require(
        SpriteFrameRenderer.render(
            source: sheet,
            adjustment: FrameAdjustment(crop: crop, offsetX: 5, offsetY: 0)
        )
    )
    #expect(spriteTestPixel(of: shiftedRight, column: 0, row: 10) == .clear)
    #expect(spriteTestPixel(of: shiftedRight, column: 4, row: 10) == .clear)
    #expect(spriteTestPixel(of: shiftedRight, column: 5, row: 10) == color)
    #expect(spriteTestPixel(of: shiftedRight, column: 19, row: 10) == color)

    let shiftedUp = try #require(
        SpriteFrameRenderer.render(
            source: sheet,
            adjustment: FrameAdjustment(crop: crop, offsetX: 0, offsetY: -5)
        )
    )
    #expect(spriteTestPixel(of: shiftedUp, column: 10, row: 0) == color)
    #expect(spriteTestPixel(of: shiftedUp, column: 10, row: 14) == color)
    #expect(spriteTestPixel(of: shiftedUp, column: 10, row: 15) == .clear)

    let shiftedDown = try #require(
        SpriteFrameRenderer.render(
            source: sheet,
            adjustment: FrameAdjustment(crop: crop, offsetX: 0, offsetY: 5)
        )
    )
    #expect(spriteTestPixel(of: shiftedDown, column: 10, row: 0) == .clear)
    #expect(spriteTestPixel(of: shiftedDown, column: 10, row: 4) == .clear)
    #expect(spriteTestPixel(of: shiftedDown, column: 10, row: 5) == color)
    #expect(spriteTestPixel(of: shiftedDown, column: 10, row: 19) == color)
}

@Test func rendererCropSpanningNeighborsIncludesBothCells() throws {
    let sheet = try #require(spriteTestSolidSheet())
    let crop = SquareCrop(x: 30, y: 20, size: 20)
    let rendered = try #require(
        SpriteFrameRenderer.render(source: sheet, adjustment: FrameAdjustment(crop: crop, offsetX: 0, offsetY: 0))
    )
    #expect(spriteTestPixel(of: rendered, column: 0, row: 10) == spriteTestCellColors[4])
    #expect(spriteTestPixel(of: rendered, column: 9, row: 10) == spriteTestCellColors[4])
    #expect(spriteTestPixel(of: rendered, column: 10, row: 10) == spriteTestCellColors[5])
    #expect(spriteTestPixel(of: rendered, column: 19, row: 10) == spriteTestCellColors[5])
    let geometry = spriteTestSheetEditing().geometry(for: .typing2)
    #expect(geometry.extendsOutsideCell(crop))
}

@Test func rendererKeepsAlphaAndOutputIsSquare() throws {
    let sheet = try #require(spriteTestImage(width: 60, height: 60) { column, row in
        guard row >= 40, column >= 40 else { return .clear }
        return SpriteTestPixel(red: 64, green: 32, blue: 16, alpha: 128)
    })
    let transparent = try #require(
        SpriteFrameRenderer.render(
            source: sheet,
            adjustment: FrameAdjustment(crop: SquareCrop(x: 0, y: 0, size: 20), offsetX: 0, offsetY: 0)
        )
    )
    #expect(transparent.width == 20)
    #expect(transparent.height == 20)
    #expect(spriteTestPixel(of: transparent, column: 10, row: 10) == .clear)
    let translucent = try #require(
        SpriteFrameRenderer.render(
            source: sheet,
            adjustment: FrameAdjustment(crop: SquareCrop(x: 40, y: 40, size: 20), offsetX: 0, offsetY: 0)
        )
    )
    let expected = SpriteTestPixel(red: 64, green: 32, blue: 16, alpha: 128)
    #expect(spriteTestPixel(of: translucent, column: 10, row: 10) == expected)
    let odd = try #require(
        SpriteFrameRenderer.render(
            source: sheet,
            adjustment: FrameAdjustment(crop: SquareCrop(x: 41, y: 41, size: 13), offsetX: 0, offsetY: 0)
        )
    )
    #expect(odd.width == 13)
    #expect(odd.height == 13)
}

@Test func rendererCappedOutputScalesDownWithNearestNeighbor() throws {
    let sheet = try #require(spriteTestSolidSheet())
    let crop = SquareCrop(x: 40, y: 20, size: 20)
    let adjustment = FrameAdjustment(crop: crop, offsetX: 0, offsetY: 0)
    let cyan = spriteTestCellColors[5]
    let capped = try #require(
        SpriteFrameRenderer.render(source: sheet, adjustment: adjustment, cappedOutputSide: 10)
    )
    #expect(capped.width == 10)
    #expect(capped.height == 10)
    #expect(spriteTestPixel(of: capped, column: 0, row: 0) == cyan)
    #expect(spriteTestPixel(of: capped, column: 9, row: 9) == cyan)

    let natural = try #require(
        SpriteFrameRenderer.render(source: sheet, adjustment: adjustment, cappedOutputSide: 40)
    )
    #expect(natural.width == 20)
    #expect(natural.height == 20)
    let image = try #require(
        SpriteFrameRenderer.renderNSImage(source: sheet, adjustment: adjustment, cappedOutputSide: 10)
    )
    #expect(image.size == NSSize(width: 10, height: 10))

    let spanning = FrameAdjustment(crop: SquareCrop(x: 30, y: 20, size: 20), offsetX: 0, offsetY: 0)
    let scaled = try #require(
        SpriteFrameRenderer.render(source: sheet, adjustment: spanning, cappedOutputSide: 10)
    )
    #expect(spriteTestPixel(of: scaled, column: 0, row: 5) == spriteTestCellColors[4])
    #expect(spriteTestPixel(of: scaled, column: 9, row: 5) == spriteTestCellColors[5])
}

@Test func rendererThumbnailScalesNearestNeighbor() throws {
    let sheet = try #require(spriteTestOrientedSheet())
    let rendered = try #require(
        SpriteFrameRenderer.render(
            source: sheet,
            adjustment: FrameAdjustment(crop: SquareCrop(x: 0, y: 40, size: 20), offsetX: 0, offsetY: 0)
        )
    )
    let thumbnail = try #require(SpriteFrameRenderer.thumbnail(source: rendered, side: 10))
    #expect(thumbnail.size == NSSize(width: 10, height: 10))
    let raster = try #require(PetFrameSourceDecoder.frameImage(from: thumbnail))
    #expect(raster.width == 10)
    #expect(raster.height == 10)
    #expect(spriteTestPixel(of: raster, column: 5, row: 0) == spriteTestCellColors[6])
    #expect(spriteTestPixel(of: raster, column: 5, row: 9) == spriteTestCellColors[6].inverted)
    #expect(SpriteFrameRenderer.thumbnail(source: rendered, side: 0) == nil)
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

// MARK: - Fixed-canvas renderer

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

@Test func canvasRendererCappedOutputScalesTheCanvas() throws {
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
