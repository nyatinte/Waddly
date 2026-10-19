import AppKit

/// One generated asset: its name, format, preview, copy action, and the outcome of that copy.
///
/// The card owns its own background and status text so the dialog only has to say what happened.
@MainActor
final class PetShareCardView: NSView {
    let copyButton: ShareActionButton
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    /// The label a copy outcome is shown and announced through.
    let statusLabel: NSTextField
    private let surface = CheckerboardView()

    init(
        copyButtonIdentifier: String,
        statusIdentifier: String,
        title: String,
        copyTitle: String,
        copyHelp: String,
        detail: String,
        preview: NSView
    ) {
        titleLabel = NSTextField(labelWithString: title)
        detailLabel = NSTextField(labelWithString: detail)
        statusLabel = NSTextField(labelWithString: "")
        copyButton = ShareActionButton(
            title: copyTitle,
            base: .quaternaryLabelColor,
            hover: .selectedContentBackgroundColor.withAlphaComponent(0.22),
            pressed: .selectedContentBackgroundColor.withAlphaComponent(0.45)
        )
        super.init(frame: .zero)
        statusLabel.identifier = NSUserInterfaceItemIdentifier(rawValue: statusIdentifier)
        copyButton.identifier = NSUserInterfaceItemIdentifier(rawValue: copyButtonIdentifier)
        configure(copyHelp: copyHelp, preview: preview)
        installConstraints(preview: preview)
        updateAppearance()
    }

    private func configure(copyHelp: String, preview: NSView) {
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.borderWidth = 1
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        copyButton.font = .systemFont(ofSize: 11)
        copyButton.contentTintColor = .labelColor
        copyButton.setAccessibilityHelp(copyHelp)
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 7
        surface.layer?.masksToBounds = true
        [titleLabel, copyButton, surface, detailLabel, statusLabel].forEach(addSubview)
        surface.addSubview(preview)
        for item in [titleLabel, copyButton, surface, preview, detailLabel, statusLabel] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
    }

    private func installConstraints(preview: NSView) {
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -5),
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            copyButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            surface.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            surface.heightAnchor.constraint(equalToConstant: 195),
            preview.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            preview.topAnchor.constraint(equalTo: surface.topAnchor),
            preview.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            detailLabel.topAnchor.constraint(equalTo: surface.bottomAnchor, constant: 7),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: detailLabel.trailingAnchor, constant: 6),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            statusLabel.centerYAnchor.constraint(equalTo: detailLabel.centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setTitle(_ text: String) {
        titleLabel.stringValue = text
    }

    func setCopyTitle(_ text: String) {
        copyButton.title = text
    }

    func setDetail(_ text: String) {
        detailLabel.stringValue = text
    }

    /// Shows what one copy actually did, next to the file it copied.
    func setStatus(_ text: String, failed: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = failed ? .systemRed : .secondaryLabelColor
    }

    private func updateAppearance() {
        layer?.backgroundColor = shareLayerColor(.controlBackgroundColor, appearance: effectiveAppearance)
        layer?.borderColor = shareLayerColor(.separatorColor, appearance: effectiveAppearance)
    }
}
