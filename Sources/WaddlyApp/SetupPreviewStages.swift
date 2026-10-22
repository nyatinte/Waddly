import AppKit

// MARK: - Empty stage

extension SetupPreviewPane {
    func setPlaceholderSymbol(_ symbol: String, message: String) {
        for arrangedSubview in placeholderStack.arrangedSubviews {
            placeholderStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .tertiaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let label = NSTextField(wrappingLabelWithString: message)
        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true

        placeholderStack.addArrangedSubview(icon)
        placeholderStack.addArrangedSubview(label)
        placeholderStack.setAccessibilityLabel(message)
    }
}
