import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
import WaddlyCore

// MARK: - Slot mapping

@Test func slotsFollowSheetCellOrderNotCategoryRows() {
    #expect(SpriteFrameSlot.allCases.count == 9)
    #expect(SpriteFrameSlot.allCases.map(\.rawValue) == Array(0 ... 8))
    #expect(SpriteFrameSlot.allCases.map(\.sheetNumber) == Array(1 ... 9))
    #expect(SpriteFrameSlot.slots(for: .idle) == [.idle1, .idle2])
    #expect(SpriteFrameSlot.slots(for: .typing) == [.typing1, .typing2, .typing3, .typing4])
    #expect(SpriteFrameSlot.slots(for: .enter) == [.enter])
    #expect(SpriteFrameSlot.slots(for: .sleep) == [.sleep1, .sleep2])
    for category in PetImageCategory.allCases {
        let slots = SpriteFrameSlot.slots(for: category)
        #expect(!slots.isEmpty)
        for (index, slot) in slots.enumerated() {
            #expect(SpriteFrameSlot.slot(category: category, index: index) == slot)
            #expect(slot.category == category)
            #expect(slot.frameIndexInCategory == index)
        }
    }
    #expect(SpriteFrameSlot.slot(category: .typing, index: 4) == nil)
    #expect(SpriteFrameSlot.slot(category: .idle, index: -1) == nil)
    #expect(SpriteFrameSlot.slot(category: .enter, index: 1) == nil)
}

@Test func slotRawValuesMapExactlyToSheetCells() throws {
    let idle = try #require(SpriteFrameSlot(rawValue: 1))
    let typing = try #require(SpriteFrameSlot(rawValue: 2))
    let enter = try #require(SpriteFrameSlot(rawValue: 6))
    let sleep = try #require(SpriteFrameSlot(rawValue: 7))
    #expect(idle == .idle2)
    #expect(typing == .typing1)
    #expect(enter == .enter)
    #expect(sleep == .sleep1)
    #expect(SpriteFrameSlot.idle1.sheetNumber == 1)
    #expect(SpriteFrameSlot.typing1.sheetNumber == 3)
    #expect(SpriteFrameSlot.enter.sheetNumber == 7)
    #expect(SpriteFrameSlot.sleep2.sheetNumber == 9)
    #expect(SpriteFrameSlot.typing4.frameIndexInCategory == 3)
    #expect(SpriteFrameSlot.enter.frameIndexInCategory == 0)
    #expect(SpriteFrameSlot.sleep2.frameIndexInCategory == 1)
}

// MARK: - Identity and geometry

@Test func sheetIdentityPlacesNominalCellsAndHasNoEdits() throws {
    let editing = spriteTestSheetEditing()
    #expect(editing.adjustments.count == 9)
    #expect(editing.sourceSides == Array(repeating: 20, count: 9))
    #expect(!editing.hasEdits)
    for slot in SpriteFrameSlot.allCases {
        let geometry = editing.geometry(for: slot)
        #expect(geometry.sourceSide == 60)
        #expect(geometry.minimumSide >= 1)
        #expect(geometry.minimumSide <= geometry.sourceSide)
        let cell = try #require(geometry.nominalCell)
        #expect(cell == SquareCrop(x: (slot.rawValue % 3) * 20, y: (slot.rawValue / 3) * 20, size: 20))
        #expect(editing.adjustment(for: slot) == FrameAdjustment(crop: cell, offsetX: 0, offsetY: 0))
        #expect(!editing.isEdited(slot))
        #expect(!geometry.extendsOutsideCell(cell))
    }
}

@Test func individualIdentityUsesEachFrameSide() {
    let sides = [10, 11, 12, 13, 14, 15, 16, 17, 18]
    let editing = SpriteFrameEditing.identity(
        mode: .individualFrames,
        sourceSides: sides,
        cellSize: 0
    )
    #expect(editing.mode == .individualFrames)
    #expect(editing.cellSize == 0)
    #expect(editing.adjustments.count == 9)
    #expect(!editing.hasEdits)
    for slot in SpriteFrameSlot.allCases {
        let geometry = editing.geometry(for: slot)
        let side = sides[slot.rawValue]
        #expect(geometry.sourceSide == side)
        #expect(geometry.nominalCell == nil)
        #expect(!geometry.extendsOutsideCell(SquareCrop(x: 0, y: 0, size: side)))
        #expect(editing.adjustment(for: slot).crop == SquareCrop(x: 0, y: 0, size: side))
    }
}

@Test func clampTranslatesIntoBoundsAndShrinksOnlyWhenNeeded() {
    let geometry = FrameEditGeometry(sourceSide: 60, cellOriginX: 40, cellOriginY: 0, cellSize: 20)
    let minimum = geometry.minimumSide
    #expect(geometry.clamp(SquareCrop(x: 40, y: 0, size: 20)) == SquareCrop(x: 40, y: 0, size: 20))
    #expect(geometry.clamp(SquareCrop(x: -5, y: -5, size: 20)) == SquareCrop(x: 0, y: 0, size: 20))
    #expect(geometry.clamp(SquareCrop(x: 50, y: 50, size: 20)) == SquareCrop(x: 40, y: 40, size: 20))
    #expect(geometry.clamp(SquareCrop(x: 10, y: 10, size: 100)) == SquareCrop(x: 0, y: 0, size: 60))
    #expect(geometry.clamp(SquareCrop(x: -100, y: -100, size: 100)) == SquareCrop(x: 0, y: 0, size: 60))
    #expect(geometry.clamp(SquareCrop(x: 10, y: 10, size: 1)) == SquareCrop(x: 10, y: 10, size: minimum))
    let once = geometry.clamp(SquareCrop(x: -4, y: 70, size: 3))
    #expect(geometry.clamp(once) == once)
}

private struct ResizeExpectation {
    let handle: SpriteCropHandle
    let deltaX: Int
    let deltaY: Int
    let expected: SquareCrop
}

@Test func resizeHandlesKeepTheCropCentred() {
    let geometry = spriteTestSheetGeometry()
    let crop = SquareCrop(x: 20, y: 20, size: 20)
    let cases = [
        ResizeExpectation(handle: .topLeft, deltaX: -5, deltaY: -5, expected: SquareCrop(x: 15, y: 15, size: 30)),
        ResizeExpectation(handle: .top, deltaX: 0, deltaY: -3, expected: SquareCrop(x: 17, y: 17, size: 26)),
        ResizeExpectation(handle: .topRight, deltaX: 2, deltaY: -5, expected: SquareCrop(x: 15, y: 15, size: 30)),
        ResizeExpectation(handle: .right, deltaX: 4, deltaY: 0, expected: SquareCrop(x: 16, y: 16, size: 28)),
        ResizeExpectation(handle: .bottomRight, deltaX: 5, deltaY: 5, expected: SquareCrop(x: 15, y: 15, size: 30)),
        ResizeExpectation(handle: .bottom, deltaX: 0, deltaY: -4, expected: SquareCrop(x: 24, y: 24, size: 12)),
        ResizeExpectation(handle: .bottomLeft, deltaX: -3, deltaY: 5, expected: SquareCrop(x: 15, y: 15, size: 30)),
        ResizeExpectation(handle: .left, deltaX: -5, deltaY: 0, expected: SquareCrop(x: 15, y: 15, size: 30))
    ]
    #expect(cases.count == SpriteCropHandle.allCases.count)
    for expectation in cases {
        let resized = geometry.resized(
            crop,
            handle: expectation.handle,
            deltaX: expectation.deltaX,
            deltaY: expectation.deltaY
        )
        #expect(resized == expectation.expected)
        #expect(2 * resized.x + resized.size == 2 * crop.x + crop.size)
        #expect(2 * resized.y + resized.size == 2 * crop.y + crop.size)
    }
}

@Test func resizeCornerFollowsTheDominantAxis() {
    let geometry = spriteTestSheetGeometry()
    let crop = SquareCrop(x: 20, y: 20, size: 20)
    #expect(geometry.resized(crop, handle: .bottomRight, deltaX: 2, deltaY: 7) == SquareCrop(x: 13, y: 13, size: 34))
    #expect(geometry.resized(crop, handle: .topLeft, deltaX: 7, deltaY: 2) == SquareCrop(x: 26, y: 26, size: 8))
}

@Test func resizeRespectsMinimumSideAndSourceBounds() {
    let geometry = spriteTestSheetGeometry()
    let crop = SquareCrop(x: 20, y: 20, size: 20)
    let shrunk = geometry.resized(crop, handle: .right, deltaX: -100, deltaY: 0)
    #expect(shrunk == SquareCrop(x: 26, y: 26, size: geometry.minimumSide))
    let expanded = geometry.resized(crop, handle: .left, deltaX: -100, deltaY: 0)
    #expect(expanded == SquareCrop(x: 0, y: 0, size: 60))
}

@Test func movedClampsAtTheSourceEdges() {
    let geometry = spriteTestSheetGeometry()
    #expect(geometry.moved(SquareCrop(x: 20, y: 20, size: 20), deltaX: 10, deltaY: -100)
        == SquareCrop(x: 30, y: 0, size: 20))
    #expect(geometry.moved(SquareCrop(x: 20, y: 20, size: 20), deltaX: -100, deltaY: 0)
        == SquareCrop(x: 0, y: 20, size: 20))
    #expect(geometry.moved(SquareCrop(x: 20, y: 20, size: 20), deltaX: 100, deltaY: 100)
        == SquareCrop(x: 40, y: 40, size: 20))
}

@Test func extendsOutsideCellReportsDriftOnlyInSheetMode() {
    let sheet = spriteTestSheetGeometry(slot: .typing1)
    #expect(!sheet.extendsOutsideCell(SquareCrop(x: 40, y: 0, size: 20)))
    #expect(sheet.extendsOutsideCell(SquareCrop(x: 39, y: 0, size: 20)))
    #expect(sheet.extendsOutsideCell(SquareCrop(x: 40, y: 1, size: 20)))
    #expect(sheet.extendsOutsideCell(SquareCrop(x: 30, y: 0, size: 20)))
    #expect(!sheet.extendsOutsideCell(SquareCrop(x: 42, y: 2, size: 16)))
    let individual = SpriteFrameEditing.identity(
        mode: .individualFrames,
        sourceSides: Array(repeating: 40, count: 9),
        cellSize: 0
    ).geometry(for: .typing1)
    #expect(individual.nominalCell == nil)
    #expect(!individual.extendsOutsideCell(SquareCrop(x: 0, y: 0, size: 40)))
    #expect(!individual.extendsOutsideCell(SquareCrop(x: -10, y: 50, size: 40)))
}

@Test func offsetsClampToTheCropSide() {
    let geometry = spriteTestSheetGeometry()
    let crop = SquareCrop(x: 20, y: 20, size: 20)
    #expect(geometry.clampedOffset(x: 100, y: -100, crop: crop) == (x: 20, y: -20))
    #expect(geometry.clampedOffset(x: 5, y: -7, crop: crop) == (x: 5, y: -7))
    #expect(geometry.clampedOffset(x: -20, y: 20, crop: crop) == (x: -20, y: 20))
}

@Test func adjustmentsNormalizeCropAndOffsetsTogether() {
    let geometry = spriteTestSheetGeometry(slot: .idle1)
    let baseline = FrameAdjustment.baseline(slot: .idle1, geometry: geometry)
    #expect(baseline == FrameAdjustment(crop: SquareCrop(x: 0, y: 0, size: 20), offsetX: 0, offsetY: 0))
    let raw = FrameAdjustment(crop: SquareCrop(x: -20, y: 70, size: 30), offsetX: 100, offsetY: -100)
    let normalized = raw.normalized(geometry: geometry)
    #expect(normalized == FrameAdjustment(crop: SquareCrop(x: 0, y: 30, size: 30), offsetX: 30, offsetY: -30))
    #expect(normalized.normalized(geometry: geometry) == normalized)
    let individual = SpriteFrameEditing.identity(
        mode: .individualFrames,
        sourceSides: Array(repeating: 24, count: 9),
        cellSize: 0
    )
    #expect(FrameAdjustment.baseline(slot: .idle1, geometry: individual.geometry(for: .idle1))
        == FrameAdjustment(crop: SquareCrop(x: 0, y: 0, size: 24), offsetX: 0, offsetY: 0))
}

// MARK: - Editing state

@Test func adjustmentsArePerSlotAndResetIndependently() {
    var editing = spriteTestSheetEditing()
    let edited = FrameAdjustment(crop: SquareCrop(x: 22, y: 2, size: 16), offsetX: 3, offsetY: -1)
    editing.setAdjustment(edited, for: .typing2)
    #expect(editing.adjustment(for: .typing2) == edited)
    #expect(editing.isEdited(.typing2))
    #expect(editing.hasEdits)
    #expect(!editing.isEdited(.typing1))
    #expect(editing.adjustments.count == 9)
    #expect(editing.adjustment(for: .typing1).crop == SquareCrop(x: 40, y: 0, size: 20))
    editing.reset(.typing2)
    #expect(!editing.hasEdits)
    editing.setAdjustment(edited, for: .idle1)
    editing.setAdjustment(edited, for: .sleep2)
    #expect(editing.hasEdits)
    editing.resetAll()
    #expect(!editing.hasEdits)
    #expect(editing.adjustments.count == 9)
}

@Test func normalizedEditingClampsEverySlotAndKeepsNineAdjustments() {
    var editing = spriteTestSheetEditing()
    editing.setAdjustment(
        FrameAdjustment(crop: SquareCrop(x: -10, y: 100, size: 0), offsetX: 999, offsetY: -999),
        for: .enter
    )
    let normalized = editing.normalized
    #expect(normalized.adjustments.count == 9)
    #expect(normalized.sourceSides == editing.sourceSides)
    for slot in SpriteFrameSlot.allCases {
        let adjustment = normalized.adjustment(for: slot)
        let geometry = normalized.geometry(for: slot)
        #expect(adjustment.normalized(geometry: geometry) == adjustment)
        #expect(adjustment.crop.size >= geometry.minimumSide)
        #expect(adjustment.crop.size <= geometry.sourceSide)
    }
    #expect(normalized.isEdited(.enter))
}

@Test func editingCodableRoundTripsAndRepairsShortArrays() throws {
    var editing = spriteTestSheetEditing()
    editing.setAdjustment(
        FrameAdjustment(crop: SquareCrop(x: 21, y: 3, size: 15), offsetX: -2, offsetY: 4),
        for: .sleep1
    )
    let data = try JSONEncoder().encode(editing)
    let decoded = try JSONDecoder().decode(SpriteFrameEditing.self, from: data)
    #expect(decoded == editing)

    let shortJSON = Data(
        #"{"mode":"sheet","sourceSides":[20],"cellSize":20,"adjustments":[]}"#.utf8
    )
    let repaired = try JSONDecoder().decode(SpriteFrameEditing.self, from: shortJSON)
    #expect(repaired.sourceSides.count == 9)
    #expect(repaired.adjustments.count == 9)
    #expect(!repaired.hasEdits)
}

@Test func editingSourceHelpersBuildIndividualEditsFromFrames() throws {
    let data = try fixturePNGData()
    var images = try #require(PetSpriteSheetImporter.frames(from: data))
    images.editingSource = nil
    let editing = try #require(PetImageEditingSource.individualEditing(for: images))
    #expect(editing.mode == .individualFrames)
    #expect(editing.cellSize == 0)
    #expect(editing.adjustments.count == 9)
    for slot in SpriteFrameSlot.allCases {
        let frame = images[slot.category][slot.frameIndexInCategory]
        let raster = try #require(PetFrameSourceDecoder.frameImage(from: frame))
        #expect(editing.geometry(for: slot).sourceSide == raster.width)
    }
    let source = try #require(PetImageEditingSource.editingSource(frames: images))
    #expect(source.editing == editing)
    #expect(source.sheetPNGData == nil)

    var incomplete = images
    incomplete[.enter] = []
    #expect(PetImageEditingSource.individualEditing(for: incomplete) == nil)
    #expect(PetImageEditingSource.editingSource(frames: incomplete) == nil)
}

func fixturePNGData() throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: "nyatinte-bot-3x3", withExtension: "png", subdirectory: "Fixtures")
    )
    return try Data(contentsOf: url)
}
