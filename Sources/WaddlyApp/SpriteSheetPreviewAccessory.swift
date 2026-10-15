import AppKit

/// Accessory for the "import this pet image?" sheet.
///
/// The 3×3 sheet is checked against light and dark backgrounds, because a transparent PNG that
/// reads well on one can hide stray fragments on the other. Technical limits that do not help the
/// decision are collapsed into one small line.
@MainActor
final class SpriteSheetPreviewAccessory: NSView {
    private enum Background: Int {
        case light
        case dark

        var color: NSColor {
            switch self {
            case .light: .white
            case .dark: NSColor(calibratedWhite: 0.09, alpha: 1)
            }
        }
    }

    private let imageView = PixelImageView()
    private let backgroundControl = NSButton()
    private let localization: LocalizationController
    private var didChooseBackground = false
    private var background = Background.light

    init(
        preview: NSImage,
        cellSize: Int,
        displaySize: CGFloat,
        localization: LocalizationController,
        prefersDarkBackground: Bool
    ) {
        self.localization = localization
        background = prefersDarkBackground ? .dark : .light
        super.init(frame: NSRect(x: 0, y: 0, width: 470, height: 296))
        addSubview(makeBackgroundControl())
        addSubview(makeImageView(preview))
        addSubview(makeTechSummary(cellSize: cellSize, displaySize: displaySize))
        addSubview(makeChecklist(width: 206, originX: 264))
        applyDefaultBackground()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyDefaultBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyDefaultBackground()
    }

    private func applyDefaultBackground() {
        guard !didChooseBackground else { return }
        apply(background)
    }

    private func apply(_ background: Background) {
        self.background = background
        imageView.layer?.backgroundColor = background.color.cgColor
        backgroundControl.state = background == .dark ? .on : .off
    }

    @objc private func changeBackground() {
        didChooseBackground = true
        apply(backgroundControl.state == .on ? .dark : .light)
    }

    private func makeBackgroundControl() -> NSButton {
        backgroundControl.setButtonType(.switch)
        backgroundControl.title = localization.string(for: .petPreviewBackground)
        backgroundControl.target = self
        backgroundControl.action = #selector(changeBackground)
        backgroundControl.frame = NSRect(x: 0, y: 272, width: 240, height: 24)
        return backgroundControl
    }

    private func makeImageView(_ preview: NSImage) -> NSImageView {
        imageView.frame = NSRect(x: 0, y: 34, width: 232, height: 232)
        imageView.image = preview
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.layer?.borderWidth = 1
        imageView.setAccessibilityLabel(localization.string(for: .a11ySpritePreview))

        let grid = SpriteSheetGridOverlay(frame: imageView.bounds)
        grid.autoresizingMask = [.width, .height]
        imageView.addSubview(grid)
        return imageView
    }

    private func makeTechSummary(cellSize: Int, displaySize: CGFloat) -> NSTextField {
        let side = cellSize * 3
        let label = NSTextField(
            wrappingLabelWithString: String(
                format: localization.string(for: .petPreviewTechSummary),
                side,
                cellSize,
                Int(displaySize)
            )
        )
        label.frame = NSRect(x: 0, y: 0, width: 240, height: 30)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func makeChecklist(width: CGFloat, originX: CGFloat) -> NSView {
        let column = NSView(frame: NSRect(x: originX, y: 0, width: width, height: 296))
        column.addSubview(makeChecklistTitle(width: width))
        column.addSubview(makeChecklistItem(.petPreviewCheckEdges, originY: 216, width: width))
        column.addSubview(makeChecklistItem(.petPreviewCheckEffects, originY: 170, width: width))
        column.addSubview(makeChecklistItem(.petPreviewPosition, originY: 104, width: width))
        return column
    }

    private func makeChecklistTitle(width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: localization.string(for: .petPreviewCheckTitle))
        label.frame = NSRect(x: 0, y: 272, width: width, height: 18)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeChecklistItem(_ key: LocalizationKey, originY: CGFloat, width: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "•  " + localization.string(for: key))
        label.frame = NSRect(x: 0, y: originY, width: width, height: 48)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .secondaryLabelColor
        return label
    }
}
