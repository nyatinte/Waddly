import AppKit

@MainActor
final class DraggableAppIconView: NSImageView, NSDraggingSource {
    var onDragStarted: (() -> Void)?

    init(localization: LocalizationController) {
        super.init(frame: .zero)
        image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        imageScaling = .scaleProportionallyUpOrDown
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        updateLocalization(localization)
    }

    private var isHovering = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyHover()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHover()
    }

    /// A light accent ring. Instant, so Reduce Motion has nothing to remove.
    private func applyHover() {
        layer?.cornerRadius = DesignTokens.Radius.card
        layer?.borderWidth = isHovering ? 1 : 0
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.backgroundColor = isHovering
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : nil
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// The guide can stay open across a language change; refresh the spoken and hover text.
    func updateLocalization(_ localization: LocalizationController) {
        let label = localization.string(for: .setupDragAppIcon)
        setAccessibilityLabel(label)
        toolTip = label
    }

    override func mouseDragged(with event: NSEvent) {
        onDragStarted?()
        let item = NSDraggingItem(pasteboardWriter: Self.pasteboardItem(for: Bundle.main.bundleURL))
        item.setDraggingFrame(bounds, contents: image)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.draggingFormation = .none
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    static func pasteboardItem(for url: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setString(url.absoluteString, forType: .URL)
        item.setString(url.absoluteString, forType: .string)
        item.setPropertyList([url.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        item.setString(
            url.absoluteString,
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
        )
        return item
    }
}
