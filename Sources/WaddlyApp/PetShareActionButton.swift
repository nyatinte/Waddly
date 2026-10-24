import AppKit

/// A template-tinted brand button cell. AppKit's disabled drawing replaces the title color with a
/// low-contrast system gray, so the brand cell draws its own content with the explicit brand color.
final class ShareActionButtonCell: NSButtonCell {
    var brandContentColor: NSColor?

    override func drawTitle(
        _ title: NSAttributedString,
        withFrame frame: NSRect,
        in controlView: NSView
    ) -> NSRect {
        guard let brandContentColor else {
            return super.drawTitle(title, withFrame: frame, in: controlView)
        }
        let colored = NSMutableAttributedString(attributedString: title)
        colored.addAttribute(
            .foregroundColor,
            value: brandContentColor,
            range: NSRange(location: 0, length: colored.length)
        )
        let titleRect = Self.centeredTitleRect(for: colored.size(), in: frame)
        colored.draw(in: titleRect)
        return titleRect
    }

    /// `NSButtonCell` vertically centers its title; drawing into the raw frame would sit at the top
    /// of the 36 pt pill. Keep the same centering when the custom color forces a manual draw.
    static func centeredTitleRect(for size: NSSize, in frame: NSRect) -> NSRect {
        NSRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        guard let brandContentColor else {
            super.drawImage(image, withFrame: frame, in: controlView)
            return
        }
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            brandContentColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: frame)
    }
}

/// A share action that shows hover, press, focus, and disabled states.
///
/// AppKit draws no hover feedback for a borderless button, so the layer tints system colors that follow the
/// appearance and the accent color. Press and focus stay native: `NSButton` tracks the press and draws the
/// focus ring around the button's bounds.
final class ShareActionButton: NSButton {
    private let baseColor: NSColor
    private let hoverColor: NSColor
    private let pressedColor: NSColor
    private var disabledFillColor: NSColor?
    private var brandTitle: String?
    private var enabledContentColor: NSColor?
    private var disabledContentColor: NSColor?
    private var brandCell: ShareActionButtonCell?
    private(set) var isHovered = false
    private var isPressed = false

    /// A secondary action on the shared 36 pt action height.
    static func secondaryAction(title: String) -> ShareActionButton {
        let button = ShareActionButton(
            title: title,
            base: .quaternaryLabelColor,
            hover: .selectedContentBackgroundColor.withAlphaComponent(0.22),
            pressed: .selectedContentBackgroundColor.withAlphaComponent(0.45)
        )
        button.applyActionMetrics()
        return button
    }

    /// The X brand action: black with a white logo and label in the light appearance, inverted in
    /// the dark appearance. The accent color is deliberately not used here; X's brand palette is
    /// black and white.
    static func primaryAction(title: String) -> ShareActionButton {
        let button = ShareActionButton(
            title: title,
            base: brandColor(light: .black, dark: .white),
            hover: brandColor(
                light: NSColor(calibratedWhite: 0.12, alpha: 1),
                dark: NSColor(calibratedWhite: 0.88, alpha: 1)
            ),
            pressed: brandColor(
                light: NSColor(calibratedWhite: 0.22, alpha: 1),
                dark: NSColor(calibratedWhite: 0.78, alpha: 1)
            )
        )
        // The X action is a brand pill rather than a rounded system action. The custom cell keeps
        // the disabled title/logo on the explicit brand color instead of the low-contrast system gray.
        let cell = ShareActionButtonCell()
        cell.brandContentColor = brandTextColor
        cell.isBordered = false
        button.cell = cell
        button.brandCell = cell
        button.isBordered = false
        button.applyActionMetrics()
        button.layer?.cornerRadius = LayoutMetrics.actionHeight / 2
        button.applyBrandContent(
            enabled: brandTextColor,
            disabled: brandColor(
                light: NSColor(calibratedWhite: 0.30, alpha: 1),
                dark: NSColor(calibratedWhite: 0.72, alpha: 1)
            ),
            disabledFill: brandColor(
                light: NSColor(calibratedWhite: 0.90, alpha: 1),
                dark: NSColor(calibratedWhite: 0.20, alpha: 1)
            )
        )
        button.setPrimaryTitle(title)
        return button
    }

    private static let brandTextColor = brandColor(light: .white, dark: .black)

    /// A black/white brand color that resolves when the button is drawn in its current appearance.
    private static func brandColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    /// The shared action metrics: 13 pt type and a 36 pt height with 12 pt side padding, matching
    /// `LayoutMetrics.actionHeight` and `actionLabel()` in the setup and character screens. The
    /// movie play overlay keeps its own 40 × 40 frame and does not call this.
    func applyActionMetrics() {
        translatesAutoresizingMaskIntoConstraints = false
        font = .systemFont(ofSize: 13)
        invalidateIntrinsicContentSize()
    }

    /// The brand fill needs the inverse of its black/white base; a plain borderless button would
    /// otherwise keep the label color. The disabled label gets its own color instead of the system
    /// opacity so the contrast stays readable in both appearances.
    func setPrimaryTitle(_ title: String) {
        brandTitle = title
        self.title = title
        updateBrandContentColor()
        invalidateIntrinsicContentSize()
    }

    private func applyBrandContent(enabled: NSColor, disabled: NSColor, disabledFill: NSColor) {
        enabledContentColor = enabled
        disabledContentColor = disabled
        disabledFillColor = disabledFill
        updateBrandContentColor()
    }

    private func updateBrandContentColor() {
        guard let brandTitle else { return }
        let color = if isEnabled {
            enabledContentColor ?? Self.brandTextColor
        } else {
            disabledContentColor ?? (enabledContentColor ?? Self.brandTextColor).withAlphaComponent(0.45)
        }
        contentTintColor = color
        brandCell?.brandContentColor = color
        attributedTitle = NSAttributedString(string: brandTitle, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: color
        ])
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 24, height: max(size.height, LayoutMetrics.actionHeight))
    }

    init(title: String, base: NSColor, hover: NSColor, pressed: NSColor) {
        baseColor = base
        hoverColor = hover
        pressedColor = pressed
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        focusRingType = .default
        updateBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isEnabled: Bool {
        didSet {
            isHovered = isHovered && isEnabled
            updateTrackingAreas()
            updateBackground()
            updateBrandContentColor()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard isEnabled else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    /// Sets the hover state the tracking area would report.
    func setHovered(_ hovered: Bool) {
        isHovered = hovered && isEnabled
        updateBackground()
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        isPressed = flag
        updateBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        let color = if !isEnabled {
            disabledFillColor ?? baseColor.withAlphaComponent(0.45)
        } else if isPressed {
            pressedColor
        } else if isHovered {
            hoverColor
        } else {
            baseColor
        }
        layer?.backgroundColor = shareLayerColor(color, appearance: effectiveAppearance)
    }
}
