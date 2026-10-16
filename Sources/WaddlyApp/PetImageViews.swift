import AppKit
import WaddlyCore

@MainActor
final class SpriteSheetGridOverlay: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let lines = NSBezierPath()
        lines.lineWidth = 1
        for division in 1 ... 2 {
            let verticalPosition = bounds.width * CGFloat(division) / 3
            let horizontalPosition = bounds.height * CGFloat(division) / 3
            lines.move(to: NSPoint(x: verticalPosition, y: bounds.minY))
            lines.line(to: NSPoint(x: verticalPosition, y: bounds.maxY))
            lines.move(to: NSPoint(x: bounds.minX, y: horizontalPosition))
            lines.line(to: NSPoint(x: bounds.maxX, y: horizontalPosition))
        }
        NSColor.separatorColor.withAlphaComponent(0.75).setStroke()
        lines.stroke()
    }
}

@MainActor
class PetImageDropView: NSView {
    var onDrop: (([URL]) -> Void)?

    /// Border drawn while no drag is in progress. The wizard uses a borderless variant.
    var idleBorderColor: NSColor = .separatorColor {
        didSet { restoreDropAppearance() }
    }

    var idleBorderWidth: CGFloat = 1 {
        didSet { restoreDropAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = idleBorderWidth
        layer?.borderColor = idleBorderColor.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(from: sender).isEmpty else { return [] }
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        restoreDropAppearance()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        restoreDropAppearance()
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func restoreDropAppearance() {
        layer?.borderColor = idleBorderColor.cgColor
        layer?.borderWidth = idleBorderWidth
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []).filter { $0.pathExtension.lowercased() == "png" }
    }
}
