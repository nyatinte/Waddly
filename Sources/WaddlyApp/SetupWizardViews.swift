import AppKit

/// Shared metrics for the setup window. The specification fixes these values so both languages lay out the same way.
enum SetupMetrics {
    static let contentSize = NSSize(width: 820, height: 520)
    static let sideInset: CGFloat = 28
    static let topInset: CGFloat = 22
    static let bottomInset: CGFloat = 20
    static let leftColumnWidth: CGFloat = 410
    static let rightColumnWidth: CGFloat = 330
    static let columnGap: CGFloat = 24
    static let footerHeight: CGFloat = 36
    static let cardCornerRadius: CGFloat = 12
    static let previewCornerRadius: CGFloat = 16
    static let optionCardHeight: CGFloat = 72
}

let setupCardInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

extension SetupWizardController {
    func localizedString(_ key: LocalizationKey) -> String {
        localization.string(for: key)
    }

    func refreshLocalization() {
        window?.title = localizedString(.setupWindowTitle)
        renderCurrentStep()
    }

    // MARK: - Text

    func makeTitle(_ key: LocalizationKey) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: localizedString(key))
        label.font = .systemFont(ofSize: 26, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    func makeSectionTitle(_ key: LocalizationKey) -> NSTextField {
        let label = NSTextField(labelWithString: localizedString(key))
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    func makeBody(_ key: LocalizationKey) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: localizedString(key))
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    func makeCaption(_ key: LocalizationKey) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: localizedString(key))
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    func makeStatus(_ key: LocalizationKey, isPositive: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: localizedString(key))
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = isPositive ? .secondaryLabelColor : .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    // MARK: - Controls

    func makePrimaryButton(_ key: LocalizationKey, action: Selector) -> NSButton {
        let button = makeButton(key, weight: .medium, action: action)
        button.bezelColor = .controlAccentColor
        button.heightAnchor.constraint(equalToConstant: SetupMetrics.footerHeight).isActive = true
        return button
    }

    func makeSecondaryButton(_ key: LocalizationKey, action: Selector) -> NSButton {
        let button = makeButton(key, weight: .regular, action: action)
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    /// A borderless, accent-coloured control for low-priority escapes such as "Set up later".
    func makeLinkButton(_ key: LocalizationKey, action: Selector) -> NSButton {
        let button = NSButton(title: localizedString(key), target: self, action: action)
        button.isBordered = false
        button.contentTintColor = .controlAccentColor
        button.font = .systemFont(ofSize: 13)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func makeButton(_ key: LocalizationKey, weight: NSFont.Weight, action: Selector) -> NSButton {
        let button = NSButton(title: localizedString(key), target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 13, weight: weight)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - Layout helpers

    func makeStack(_ views: [NSView], fullWidth: [NSView] = []) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        // The stack already owns these views, so the width anchors share an ancestor.
        for view in fullWidth where views.contains(where: { $0 === view }) {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    func makeCard(_ content: NSView, insets: NSEdgeInsets = setupCardInsets) -> NSView {
        let card = NSVisualEffectView()
        card.material = .contentBackground
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = SetupMetrics.cardCornerRadius
        card.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -insets.bottom)
        ])
        return card
    }

    /// Numbered recipe rows. Numbers keep a short procedure scannable without a paragraph.
    func makeNumberedCard(_ keys: [LocalizationKey]) -> NSView {
        let rows = keys.enumerated().map { index, key in
            makeSymbolRow(symbol: "\(index + 1).circle.fill", key: key, tint: .controlAccentColor)
        }
        return makeVerticalCard(rows)
    }

    private func makeVerticalCard(_ rows: [NSStackView]) -> NSView {
        let stack = makeStack(rows, fullWidth: rows)
        stack.spacing = 8
        return makeCard(stack)
    }

    func makeSymbolRow(symbol: String, key: LocalizationKey, tint: NSColor) -> NSStackView {
        let badge = NSImageView()
        badge.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        badge.contentTintColor = tint
        badge.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 18).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let label = NSTextField(wrappingLabelWithString: localizedString(key))
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [badge, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    func makeIconCard(symbol: String, titleKey: LocalizationKey, detailKey: LocalizationKey) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .controlAccentColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26)
        ])
        return makeCard(makeRow(icon: icon, titleKey: titleKey, detailKey: detailKey))
    }

    func makeRow(icon: NSView, titleKey: LocalizationKey, detailKey: LocalizationKey) -> NSStackView {
        let title = NSTextField(labelWithString: localizedString(titleKey))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let text = makeStack([title, makeBody(detailKey)])
        text.spacing = 4
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }
}
