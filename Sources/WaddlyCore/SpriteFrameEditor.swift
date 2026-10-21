import AppKit

/// One cell of the 3×3 sprite sheet, in sheet-file order (cells 01–09).
///
/// The mapping is intentionally not row-grouped by category: cells 03–06 are typing, 07 is enter,
/// and 08–09 are sleep, matching the sprite sheet the app ships with.
public enum SpriteFrameSlot: Int, CaseIterable, Sendable, Codable {
    case idle1 = 0
    case idle2
    case typing1
    case typing2
    case typing3
    case typing4
    case enter
    case sleep1
    case sleep2

    /// The animation category this sheet cell belongs to.
    public var category: PetImageCategory {
        switch self {
        case .idle1, .idle2:
            .idle
        case .typing1, .typing2, .typing3, .typing4:
            .typing
        case .enter:
            .enter
        case .sleep1, .sleep2:
            .sleep
        }
    }

    /// The frame's position inside its category's animation order.
    public var frameIndexInCategory: Int {
        switch self {
        case .idle1:
            0
        case .idle2:
            1
        case .typing1:
            0
        case .typing2:
            1
        case .typing3:
            2
        case .typing4:
            3
        case .enter:
            0
        case .sleep1:
            0
        case .sleep2:
            1
        }
    }

    /// 1-based sheet cell number: cell 01 is the top-left cell.
    public var sheetNumber: Int {
        rawValue + 1
    }

    /// The sheet cell for a category frame index, or `nil` when the index is out of range.
    public static func slot(category: PetImageCategory, index: Int) -> SpriteFrameSlot? {
        let matches = slots(for: category)
        guard matches.indices.contains(index) else { return nil }
        return matches[index]
    }

    /// Every sheet cell that belongs to `category`, in sheet order.
    public static func slots(for category: PetImageCategory) -> [SpriteFrameSlot] {
        allCases.filter { $0.category == category }
    }
}

/// A square crop in source pixels, with the origin at the top-left and +Y pointing down.
public struct SquareCrop: Equatable, Sendable, Codable {
    // `x` and `y` are fixed by the crop contract; the UI reads them directly.
    // swiftlint:disable:next identifier_name
    public var x: Int
    // swiftlint:disable:next identifier_name
    public var y: Int
    public var size: Int

    // swiftlint:disable:next identifier_name
    public init(x: Int, y: Int, size: Int) {
        self.x = x
        self.y = y
        self.size = size
    }
}

/// The eight interactive handles of a square crop overlay.
public enum SpriteCropHandle: CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

/// Bounds and minimum side for one slot's crop.
///
/// `sourceSide` is the sheet side in sheet mode and the individual frame side otherwise.
/// `cellOriginX`/`cellOriginY`/`cellSize` describe the nominal cell and are `nil` in individual mode.
/// Coordinates are top-left based and +Y points down (UI space).
public struct FrameEditGeometry: Equatable, Sendable {
    public var sourceSide: Int
    public var cellOriginX: Int?
    public var cellOriginY: Int?
    public var cellSize: Int?
    public var minimumSide: Int

    public init(
        sourceSide: Int,
        cellOriginX: Int?,
        cellOriginY: Int?,
        cellSize: Int?
    ) {
        self.sourceSide = sourceSide
        self.cellOriginX = cellOriginX
        self.cellOriginY = cellOriginY
        self.cellSize = cellSize
        minimumSide = Self.minimumSide(sourceSide: sourceSide, cellSize: cellSize)
    }

    /// The smallest crop a handle may shrink to.
    ///
    /// Scaled to the source so tiny fixtures (a 6 px sheet, a 2 px cell) never get a minimum that is
    /// larger than the source itself.
    private static func minimumSide(sourceSide: Int, cellSize: Int?) -> Int {
        let reference = max(8, (cellSize ?? sourceSide) / 8)
        return max(1, min(sourceSide, reference))
    }

    /// The nominal sheet cell, or `nil` in individual mode.
    public var nominalCell: SquareCrop? {
        guard let cellOriginX, let cellOriginY, let cellSize, cellSize > 0 else { return nil }
        return SquareCrop(x: cellOriginX, y: cellOriginY, size: cellSize)
    }

    /// Moves `crop` inside the source bounds, shrinking it only when it cannot fit.
    public func clamp(_ crop: SquareCrop) -> SquareCrop {
        guard sourceSide > 0 else { return crop }
        let side = min(max(crop.size, effectiveMinimumSide), sourceSide)
        let originX = min(max(crop.x, 0), sourceSide - side)
        let originY = min(max(crop.y, 0), sourceSide - side)
        return SquareCrop(x: originX, y: originY, size: side)
    }

    /// Resizes `crop` from `handle`, keeping it square and anchoring the opposite edge or corner.
    ///
    /// Corner drags follow the dominant axis so a diagonal drag never double-applies both deltas.
    /// The result is then clamped into the source bounds.
    public func resized(
        _ crop: SquareCrop,
        handle: SpriteCropHandle,
        deltaX: Int,
        deltaY: Int
    ) -> SquareCrop {
        let growth = growth(handle: handle, deltaX: deltaX, deltaY: deltaY)
        let newSize = max(crop.size + growth, effectiveMinimumSide)
        var newX = crop.x
        var newY = crop.y
        switch handle {
        case .topLeft, .left, .bottomLeft:
            newX = crop.x + crop.size - newSize
        case .topRight, .right, .bottomRight, .top, .bottom:
            newX = crop.x
        }
        switch handle {
        case .topLeft, .top, .topRight:
            newY = crop.y + crop.size - newSize
        case .bottomLeft, .bottom, .bottomRight, .left, .right:
            newY = crop.y
        }
        return clamp(SquareCrop(x: newX, y: newY, size: newSize))
    }

    /// Translates `crop` by the delta and clamps it back into the source bounds.
    public func moved(_ crop: SquareCrop, deltaX: Int, deltaY: Int) -> SquareCrop {
        clamp(SquareCrop(x: crop.x + deltaX, y: crop.y + deltaY, size: crop.size))
    }

    /// Whether `crop` leaves the nominal cell, which the editor surfaces as a drift warning.
    public func extendsOutsideCell(_ crop: SquareCrop) -> Bool {
        guard let cell = nominalCell else { return false }
        return crop.x < cell.x || crop.y < cell.y
            || crop.x + crop.size > cell.x + cell.size
            || crop.y + crop.size > cell.y + cell.size
    }

    // swiftlint:disable identifier_name
    /// Clamps an alignment offset to one crop side in each direction.
    public func clampedOffset(x: Int, y: Int, crop: SquareCrop) -> (x: Int, y: Int) {
        let limit = max(0, crop.size)
        return (min(max(x, -limit), limit), min(max(y, -limit), limit))
    }

    // swiftlint:enable identifier_name

    private var effectiveMinimumSide: Int {
        guard sourceSide > 0 else { return 1 }
        return max(1, min(minimumSide, sourceSide))
    }

    private func growth(handle: SpriteCropHandle, deltaX: Int, deltaY: Int) -> Int {
        let factors = Self.axisFactors(for: handle)
        let horizontal = factors.horizontal * deltaX
        let vertical = factors.vertical * deltaY
        switch (factors.horizontal, factors.vertical) {
        case (0, _):
            return vertical
        case (_, 0):
            return horizontal
        case (_, _):
            return abs(deltaX) >= abs(deltaY) ? horizontal : vertical
        }
    }

    /// The signed axes a handle drags: edges move one axis, corners move both.
    private static func axisFactors(for handle: SpriteCropHandle) -> (horizontal: Int, vertical: Int) {
        switch handle {
        case .left:
            (-1, 0)
        case .right:
            (1, 0)
        case .top:
            (0, -1)
        case .bottom:
            (0, 1)
        case .topLeft:
            (-1, -1)
        case .topRight:
            (1, -1)
        case .bottomRight:
            (1, 1)
        case .bottomLeft:
            (-1, 1)
        }
    }
}

/// One slot's crop plus the alignment offset used to nudge the frame inside that crop.
public struct FrameAdjustment: Equatable, Sendable, Codable {
    public var crop: SquareCrop
    public var offsetX: Int
    public var offsetY: Int

    public init(crop: SquareCrop, offsetX: Int, offsetY: Int) {
        self.crop = crop
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    /// The unedited adjustment for `slot`: the nominal cell in sheet mode, the whole frame otherwise.
    public static func baseline(slot: SpriteFrameSlot, geometry: FrameEditGeometry) -> FrameAdjustment {
        if let cell = geometry.nominalCell {
            return FrameAdjustment(crop: cell, offsetX: 0, offsetY: 0)
        }
        return FrameAdjustment(
            crop: SquareCrop(x: 0, y: 0, size: max(0, geometry.sourceSide)),
            offsetX: 0,
            offsetY: 0
        )
    }

    /// The adjustment with its crop and offsets clamped into `geometry`'s bounds.
    public func normalized(geometry: FrameEditGeometry) -> FrameAdjustment {
        let clampedCrop = geometry.clamp(crop)
        let offset = geometry.clampedOffset(x: offsetX, y: offsetY, crop: clampedCrop)
        return FrameAdjustment(crop: clampedCrop, offsetX: offset.x, offsetY: offset.y)
    }
}
