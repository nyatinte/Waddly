import AppKit

// MARK: - Drag guide

extension SetupPreviewPane {
    /// Built once per pane; rebuilt only when localization arrives.
    func buildGuideIfNeeded() {
        guard let localization else { return }
        for arrangedSubview in guideStack.arrangedSubviews {
            guideStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        isGuideBuilt = true
        guideLanguage = localization.activeLocalization

        let list = makeMockSettingsList(localization)
        let icon = DraggableAppIconView(localization: localization)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56)
        ])
        let arrow = NSImageView()
        arrow.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)
        arrow.contentTintColor = .controlAccentColor
        arrow.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        arrow.translatesAutoresizingMaskIntoConstraints = false

        let iconRow = NSStackView(views: [icon, arrow])
        iconRow.orientation = .horizontal
        iconRow.alignment = .centerY
        iconRow.spacing = 10
        iconRow.translatesAutoresizingMaskIntoConstraints = false

        let caption = NSTextField(labelWithString: localization.string(for: .setupDropGuideCaption))
        caption.font = .systemFont(ofSize: 12, weight: .medium)
        caption.textColor = .secondaryLabelColor
        caption.translatesAutoresizingMaskIntoConstraints = false

        guideStack.addArrangedSubview(list)
        guideStack.addArrangedSubview(iconRow)
        guideStack.addArrangedSubview(caption)
    }

    /// A deliberately schematic list: it must read as "this is where it goes", not as the real pane.
    private func makeMockSettingsList(_ localization: LocalizationController) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let header = NSTextField(labelWithString: localization.string(for: .setupDropGuideListTitle))
        header.font = .systemFont(ofSize: 11, weight: .semibold)

        // Nameless rows on purpose: naming real apps inside our own UI would imply they are
        // registered, and it has no business borrowing other products' names.
        let rows = NSStackView(views: [
            makePlaceholderRow(nameWidth: 74),
            makePlaceholderRow(nameWidth: 58),
            makeDropSlot(),
            makeMockTools()
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        rows.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [header, rows])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 236),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            rows.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return card
    }

    /// A grey stand-in for one row of the settings list.
    private func makePlaceholderRow(nameWidth: CGFloat) -> NSStackView {
        let icon = makePlaceholder(width: 11, height: 11, radius: 3)
        let name = makePlaceholder(width: nameWidth, height: 7, radius: 3.5)
        let toggle = makePlaceholder(width: 24, height: 14, radius: 7)

        let spacer = NSView()
        let row = NSStackView(views: [icon, name, spacer, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makePlaceholder(width: CGFloat, height: CGFloat, radius: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.3).cgColor
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height)
        ])
        return view
    }

    private func makeDropSlot() -> DashedDropSlotView {
        let slot = DashedDropSlotView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return slot
    }

    private func makeMockTools() -> NSTextField {
        let label = NSTextField(labelWithString: "＋   －")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        return label
    }
}

/// Dashed outline showing exactly where the dragged app will land.
@MainActor
final class DashedDropSlotView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
        path.lineWidth = 1.5
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}

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
