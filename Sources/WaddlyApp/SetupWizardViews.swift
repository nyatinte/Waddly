import AppKit

extension SetupWizardController {
    func makeTitle(_ key: String) -> NSTextField {
        let label = NSTextField(labelWithString: localizedString(key))
        label.font = .systemFont(ofSize: 25, weight: .bold)
        return label
    }

    func makeDescription(_ key: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: localizedString(key))
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        return label
    }

    func makeInfoCard(symbol: String, titleKey: String, detailKey: String) -> NSView {
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
