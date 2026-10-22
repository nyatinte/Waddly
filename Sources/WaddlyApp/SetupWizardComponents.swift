import AppKit

@MainActor
final class DraggableAppIconView: NSImageView, NSDraggingSource {
    init(localization: LocalizationController) {
        super.init(frame: .zero)
        image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        imageScaling = .scaleProportionallyUpOrDown
        translatesAutoresizingMaskIntoConstraints = false
        updateLocalization(localization)
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
