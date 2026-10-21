import AppKit

/// How the current pet's frames are edited: cropped from one sheet, or from nine separate images.
public enum SpriteFrameEditingMode: String, Equatable, Sendable, Codable {
    case sheet
    case individualFrames
}

/// The persisted per-slot crop and alignment state for a pet.
public struct SpriteFrameEditing: Equatable, Sendable, Codable {
    public var mode: SpriteFrameEditingMode
    /// Exactly nine source sides, one per slot. In sheet mode every entry equals `cellSize`.
    public var sourceSides: [Int]
    /// The working cell side in sheet mode, or zero in individual mode.
    public var cellSize: Int
    /// Exactly nine adjustments, in slot order.
    public var adjustments: [FrameAdjustment]

    public init(
        mode: SpriteFrameEditingMode,
        sourceSides: [Int],
        cellSize: Int,
        adjustments: [FrameAdjustment]
    ) {
        self.mode = mode
        self.sourceSides = Self.canonicalSides(sourceSides, mode: mode, cellSize: cellSize)
        self.cellSize = cellSize
        self.adjustments = []
        self.adjustments = Self.canonicalAdjustments(adjustments, editing: self)
    }

    /// The unedited editing state for `mode`: every slot at its baseline crop and zero offset.
    public static func identity(
        mode: SpriteFrameEditingMode,
        sourceSides: [Int],
        cellSize: Int
    ) -> SpriteFrameEditing {
        SpriteFrameEditing(mode: mode, sourceSides: sourceSides, cellSize: cellSize, adjustments: [])
    }

    public func geometry(for slot: SpriteFrameSlot) -> FrameEditGeometry {
        switch mode {
        case .sheet:
            let cell = cellSize > 0 ? cellSize : sourceSide(at: slot)
            let origin = Self.cellOrigin(for: slot, cellSize: cell)
            return FrameEditGeometry(
                sourceSide: cell * 3,
                cellOriginX: origin.x,
                cellOriginY: origin.y,
                cellSize: cell
            )
        case .individualFrames:
            return FrameEditGeometry(
                sourceSide: sourceSide(at: slot),
                cellOriginX: nil,
                cellOriginY: nil,
                cellSize: nil
            )
        }
    }

    public func adjustment(for slot: SpriteFrameSlot) -> FrameAdjustment {
        let index = slot.rawValue
        guard adjustments.indices.contains(index) else {
            return FrameAdjustment.baseline(slot: slot, geometry: geometry(for: slot))
        }
        return adjustments[index]
    }

    public mutating func setAdjustment(_ adjustment: FrameAdjustment, for slot: SpriteFrameSlot) {
        var canonical = Self.canonicalAdjustments(adjustments, editing: self)
        canonical[slot.rawValue] = adjustment
        adjustments = canonical
    }

    /// Whether `slot` differs from its unedited baseline.
    public func isEdited(_ slot: SpriteFrameSlot) -> Bool {
        adjustment(for: slot) != FrameAdjustment.baseline(slot: slot, geometry: geometry(for: slot))
    }

    public var hasEdits: Bool {
        SpriteFrameSlot.allCases.contains { isEdited($0) }
    }

    public mutating func reset(_ slot: SpriteFrameSlot) {
        setAdjustment(
            FrameAdjustment.baseline(slot: slot, geometry: geometry(for: slot)),
            for: slot
        )
    }

    public mutating func resetAll() {
        adjustments = SpriteFrameSlot.allCases.map {
            FrameAdjustment.baseline(slot: $0, geometry: geometry(for: $0))
        }
    }

    /// A copy with every adjustment clamped into its geometry and arrays exactly nine long.
    public var normalized: SpriteFrameEditing {
        let clamped = SpriteFrameSlot.allCases.map { slot in
            adjustment(for: slot).normalized(geometry: geometry(for: slot))
        }
        return SpriteFrameEditing(
            mode: mode,
            sourceSides: sourceSides,
            cellSize: cellSize,
            adjustments: clamped
        )
    }

    private func sourceSide(at slot: SpriteFrameSlot) -> Int {
        guard sourceSides.indices.contains(slot.rawValue) else {
            return mode == .sheet ? max(0, cellSize) : 0
        }
        return max(0, sourceSides[slot.rawValue])
    }

    private static func cellOrigin(for slot: SpriteFrameSlot, cellSize: Int) -> (x: Int, y: Int) {
        let side = max(0, cellSize)
        return (x: (slot.rawValue % 3) * side, y: (slot.rawValue / 3) * side)
    }

    private static func canonicalSides(
        _ sides: [Int],
        mode: SpriteFrameEditingMode,
        cellSize: Int
    ) -> [Int] {
        let count = SpriteFrameSlot.allCases.count
        if mode == .sheet, cellSize > 0 {
            return Array(repeating: cellSize, count: count)
        }
        return (0 ..< count).map { index in
            guard sides.indices.contains(index) else { return max(0, cellSize) }
            return max(0, sides[index])
        }
    }

    private static func canonicalAdjustments(
        _ adjustments: [FrameAdjustment],
        editing: SpriteFrameEditing
    ) -> [FrameAdjustment] {
        SpriteFrameSlot.allCases.map { slot in
            let index = slot.rawValue
            guard adjustments.indices.contains(index) else {
                return FrameAdjustment.baseline(slot: slot, geometry: editing.geometry(for: slot))
            }
            return adjustments[index]
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case sourceSides
        case cellSize
        case adjustments
    }

    /// Decodes through the normalizing initializer so a hand-edited sidecar cannot leave the arrays
    /// malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            mode: container.decode(SpriteFrameEditingMode.self, forKey: .mode),
            sourceSides: container.decode([Int].self, forKey: .sourceSides),
            cellSize: container.decode(Int.self, forKey: .cellSize),
            adjustments: container.decode([FrameAdjustment].self, forKey: .adjustments)
        )
    }
}

/// The sheet PNG and per-slot edits a pet's frames were produced from.
public struct PetImageEditingSource: Sendable {
    public var editing: SpriteFrameEditing
    /// The working sheet PNG (at most the importer's file limit), or `nil` for individual frames.
    public var sheetPNGData: Data?

    public init(editing: SpriteFrameEditing, sheetPNGData: Data?) {
        self.editing = editing
        self.sheetPNGData = sheetPNGData
    }

    /// Individual-frame editing for a legacy saved pet, or `nil` when a frame is missing or not square.
    public static func individualEditing(for images: PetImageSet) -> SpriteFrameEditing? {
        var sides: [Int] = []
        for slot in SpriteFrameSlot.allCases {
            let frames = images[slot.category]
            let index = slot.frameIndexInCategory
            guard frames.indices.contains(index),
                  let raster = frames[index].cgImage(forProposedRect: nil, context: nil, hints: nil),
                  raster.width > 0, raster.width == raster.height
            else { return nil }
            sides.append(raster.width)
        }
        return SpriteFrameEditing.identity(
            mode: .individualFrames,
            sourceSides: sides,
            cellSize: 0
        )
    }

    /// The source a frame set should be edited from: its own sheet source, or an individual one.
    public static func editingSource(frames: PetImageSet) -> PetImageEditingSource? {
        if let existing = frames.editingSource {
            return existing
        }
        guard let editing = individualEditing(for: frames) else { return nil }
        return PetImageEditingSource(editing: editing, sheetPNGData: nil)
    }
}
