import AppKit

extension SetupWizardController {
    func localizedString(_ key: LocalizationKey) -> String {
        localization.string(for: key)
    }

    func refreshLocalization() {
        window?.title = localizedString(.setupWindowTitle)
        renderCurrentStep()
    }
}

extension SetupWizardController {
    func makeTitle(_ key: LocalizationKey) -> NSTextField {
        let label = NSTextField(labelWithString: localizedString(key))
        label.font = .systemFont(ofSize: 25, weight: .bold)
        return label
    }

    func makeDescription(_ key: LocalizationKey) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: localizedString(key))
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        return label
    }

    func makeInfoCard(symbol: String, titleKey: LocalizationKey, detailKey: LocalizationKey) -> NSView {
        let card = NSVisualEffectView()
        card.material = .contentBackground
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: localizedString(titleKey))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let text = makeStack([title, makeDescription(detailKey)])
        text.spacing = 5

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 96)
        ])
        return card
    }

    func makeDraggableAppCard() -> NSView {
        let card = NSVisualEffectView()
        card.material = .contentBackground
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false

        let icon = DraggableAppIconView(localization: localization)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: localizedString(.setupDragAppTitle))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let text = makeStack([title, makeDescription(.setupDragAppDescription)])
        text.spacing = 5
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
        return card
    }

    func makeStack(_ views: [NSView], fullWidth: [NSView] = []) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in fullWidth {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }
}

@MainActor
final class DraggableAppIconView: NSImageView, NSDraggingSource {
    init(localization: LocalizationController) {
        super.init(frame: .zero)
        image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        imageScaling = .scaleProportionallyUpOrDown
        setAccessibilityLabel(localization.string(for: .setupDragAppIcon))
        toolTip = localization.string(for: .setupDragAppIcon)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDragged(with event: NSEvent) {
        let appURL = Bundle.main.bundleURL as NSURL
        let item = NSDraggingItem(pasteboardWriter: appURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
