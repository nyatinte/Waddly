import AppKit
import AVKit

/// Resolves a dynamic system color for an appearance, so layer fills follow light, dark, and contrast settings.
@MainActor
func shareLayerColor(_ color: NSColor, appearance: NSAppearance) -> CGColor {
    var result = color.cgColor
    appearance.performAsCurrentDrawingAppearance { result = color.cgColor }
    return result
}

/// The official X glyph, used unmodified as a template so the brand fill can tint it black or white.
/// The viewBox keeps 12 pt of clear space on the left for the pill's curved edge.
enum ShareXLogo {
    private static let viewBox = (x: -813.185, width: 2026.37, height: 1226.37)
    private static let glyph = """
    <svg xmlns="http://www.w3.org/2000/svg"
         viewBox="-813.185 0 2026.37 1226.37">
      <path d="M306.615 79.694H144.011L892.476 1150.3h162.604ZM0 0h357.328l309.814 450.883
               L1055.03 0h105.86L714.15 519.295 1200 1226.37H842.672L515.493 750.215
               L105.866 1226.37H0l468.485-544.568Z"/>
    </svg>
    """

    static func image(height: CGFloat) -> NSImage? {
        guard let data = glyph.data(using: .utf8), let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: height * viewBox.width / viewBox.height, height: height)
        image.isTemplate = true
        return image
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
        button.applyActionMetrics()
        // The X action is a brand pill rather than a rounded system action.
        button.layer?.cornerRadius = LayoutMetrics.actionHeight / 2
        button.contentTintColor = brandTextColor
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
    /// otherwise keep the label color.
    func setPrimaryTitle(_ title: String) {
        self.title = title
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: Self.brandTextColor
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
            baseColor.withAlphaComponent(0.45)
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

/// A checkerboard surface that keeps transparent sprite frames readable in both appearances.
@MainActor
final class CheckerboardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let tile: CGFloat = 14
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let light = NSColor(calibratedWhite: isDark ? 0.30 : 0.97, alpha: 1)
        let dark = NSColor(calibratedWhite: isDark ? 0.22 : 0.88, alpha: 1)
        for row in 0 ..< Int(ceil(bounds.height / tile)) {
            for column in 0 ..< Int(ceil(bounds.width / tile)) {
                ((row + column).isMultiple(of: 2) ? light : dark).setFill()
                NSRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile).fill()
            }
        }
    }
}

/// Plays the exported movie in place, so the preview shows the exact file that copying and posting use.
@MainActor
final class PetMoviePreviewView: NSView {
    private var playerView: AVPlayerView?
    private let posterView = NSImageView()
    private let playButton = ShareActionButton(
        title: "",
        base: NSColor.black.withAlphaComponent(0.55),
        hover: NSColor.black.withAlphaComponent(0.7),
        pressed: NSColor.black.withAlphaComponent(0.85)
    )
    private var movieURL: URL?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var playLabel = ""
    private var pauseLabel = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier(rawValue: "share.moviePreview")
        posterView.imageScaling = .scaleProportionallyUpOrDown
        posterView.imageAlignment = .alignCenter
        posterView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(posterView)
        playButton.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.playButton")
        playButton.layer?.cornerRadius = 20
        playButton.image = PetMoviePreviewView.symbol("play.fill")
        playButton.imagePosition = .imageOnly
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.target = self
        playButton.action = #selector(togglePlayback)
        addSubview(playButton)
        NSLayoutConstraint.activate([
            posterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            posterView.trailingAnchor.constraint(equalTo: trailingAnchor),
            posterView.topAnchor.constraint(equalTo: topAnchor),
            posterView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            playButton.widthAnchor.constraint(equalToConstant: 40),
            playButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func loadMovie(at url: URL, poster: NSImage?) {
        movieURL = url
        posterView.image = poster
    }

    func setAccessibilityLabels(play: String, pause: String) {
        playLabel = play
        pauseLabel = pause
        setPlaying(player?.timeControlStatus == .playing)
    }

    func stop() {
        player?.pause()
        playerView?.player = nil
        playerView?.removeFromSuperview()
        playerView = nil
        posterView.isHidden = false
        posterView.image = nil
        movieURL = nil
        player = nil
        setPlaying(false)
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    @objc private func togglePlayback() {
        if player == nil, let movieURL {
            let player = AVPlayer(url: movieURL)
            self.player = player
            let playerView = AVPlayerView()
            playerView.controlsStyle = .none
            playerView.videoGravity = .resizeAspect
            playerView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(playerView, positioned: .below, relativeTo: playButton)
            NSLayoutConstraint.activate([
                playerView.centerXAnchor.constraint(equalTo: centerXAnchor),
                playerView.widthAnchor.constraint(equalTo: playerView.heightAnchor),
                playerView.topAnchor.constraint(equalTo: topAnchor),
                playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            self.playerView = playerView
            playerView.player = player
            posterView.isHidden = true
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.resetPlayback() }
            }
        }
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            setPlaying(false)
        } else {
            if player.currentItem?.currentTime() == player.currentItem?.duration {
                player.seek(to: .zero)
            }
            player.play()
            setPlaying(true)
        }
    }

    private func setPlaying(_ isPlaying: Bool) {
        playButton.image = Self.symbol(isPlaying ? "pause.fill" : "play.fill")
        playButton.setAccessibilityLabel(isPlaying ? pauseLabel : playLabel)
    }

    /// The overlay sits on the animation itself, so the symbol must stay white in both appearances.
    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white]))
    }

    private func resetPlayback() {
        player?.pause()
        player?.seek(to: .zero)
        setPlaying(false)
    }
}
