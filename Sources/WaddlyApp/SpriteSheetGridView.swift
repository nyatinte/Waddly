import AppKit

/// The 3×3 view of the registered sheet, so the cells can be checked at a glance.
@MainActor
final class SpriteSheetGridView: NSView {
    private var cells: [NSImageView] = []
    private var background: NSColor = .white

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        for _ in 0 ..< 9 {
            let cell = PixelImageView()
            cell.imageScaling = .scaleProportionallyUpOrDown
            addSubview(cell)
            cells.append(cell)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setFrames(_ frames: [NSImage]) {
        for (index, cell) in cells.enumerated() {
            cell.image = index < frames.count ? frames[index] : nil
        }
        needsLayout = true
    }

    func setBackground(_ color: NSColor) {
        background = color
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)
        let cellSide = side / 3
        for (index, cell) in cells.enumerated() {
            let row = index / 3
            let column = index % 3
            cell.frame = NSRect(
                x: CGFloat(column) * cellSide,
                y: bounds.height - CGFloat(row + 1) * cellSide,
                width: cellSide,
                height: cellSide
            )
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        dirtyRect.fill()
        let side = min(bounds.width, bounds.height)
        let cellSide = side / 3
        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = 1
        for division in 1 ... 2 {
            let offset = CGFloat(division) * cellSide
            lines.move(to: NSPoint(x: bounds.minX + offset, y: bounds.minY))
            lines.line(to: NSPoint(x: bounds.minX + offset, y: bounds.minY + side))
            lines.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - offset))
            lines.line(to: NSPoint(x: bounds.minX + side, y: bounds.maxY - offset))
        }
        lines.stroke()
    }
}
