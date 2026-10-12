import AppKit
import AVKit

@MainActor
final class PetShareDialogView: NSView {
    var onCopySprite: (() -> Void)?
    var onCopyMovie: (() -> Void)?
    var onOpenX: (() -> Void)?
    private let localization: LocalizationController
    private let moviePreview = PetMoviePreviewView()
    private let spriteImage = NSImageView()
    private let loading = NSStackView()
    private let loadingLabel: NSTextField
    private let movieCopyButton: NSButton
    private let spriteCopyButton: NSButton
    private let cards: NSStackView
    private let spinner = NSProgressIndicator()
    private let postTitle: NSTextField
    private let xRow = NSView()
    private let xIdentity = ShareXIdentityView()
    private let xMark = ShareXLogoView()
    private let xLabel: NSTextField

    init(localization: LocalizationController) {
        self.localization = localization
        loadingLabel = NSTextField(labelWithString: localization.string(for: .shareLoading))
        movieCopyButton = NSButton(title: localization.string(for: .shareCopy), target: nil, action: nil)
        spriteCopyButton = NSButton(title: localization.string(for: .shareCopy), target: nil, action: nil)
        postTitle = NSTextField(labelWithString: localization.string(for: .sharePost))
        xLabel = NSTextField(labelWithString: localization.string(for: .shareXCreate))
        let videoCard = Self.makeCard(
            title: localization.string(for: .shareVideo), copyButton: movieCopyButton,
            preview: moviePreview, detail: "MP4"
        )
        let spriteCard = Self.makeCard(
            title: localization.string(for: .shareSprite), copyButton: spriteCopyButton,
            preview: spriteImage, detail: "PNG · 9"
        )
        cards = NSStackView(views: [videoCard, spriteCard])
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configureAppearance()
        installSubviews()
        installActions()
        installConstraints()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAssets(spriteURL: URL, movieURL: URL, moviePoster: NSImage?) {
        spriteImage.image = NSImage(contentsOf: spriteURL)
        moviePreview.loadMovie(at: movieURL, poster: moviePoster)
        loading.isHidden = true
        cards.isHidden = false
    }

    func showError() {
        spinner.stopAnimation(nil)
        loading.arrangedSubviews.forEach { loading.removeArrangedSubview($0); $0.removeFromSuperview() }
        loading.addArrangedSubview(NSTextField(wrappingLabelWithString: localization.string(for: .shareError)))
    }

    func stopPlayback() {
        moviePreview.stop()
    }

    func didCopySprite() {
        spriteCopyButton.title = localization.string(for: .shareCopied)
    }

    func didCopyMovie() {
        movieCopyButton.title = localization.string(for: .shareCopied)
    }

    @objc private func copySprite() {
        onCopySprite?()
    }

    @objc private func copyMovie() {
        onCopyMovie?()
    }

    @objc private func openX() {
        onOpenX?()
    }

    private func configureAppearance() {
        postTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        postTitle.textColor = .secondaryLabelColor
        xRow.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.postRow")
        xIdentity.addArrangedSubview(xMark)
        xIdentity.addArrangedSubview(xLabel)
        xRow.wantsLayer = true
        xRow.layer?.backgroundColor = NSColor(calibratedRed: 0.933, green: 0.933, blue: 0.945, alpha: 1).cgColor
        xRow.layer?.cornerRadius = 10
        xIdentity.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.xIdentity")
        xIdentity.orientation = .horizontal
        xIdentity.alignment = .centerY
        xIdentity.spacing = 6
        xMark.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.xLogo")
        spriteImage.identifier = NSUserInterfaceItemIdentifier(rawValue: "share.spritePreview")
        xLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        spriteImage.imageScaling = .scaleProportionallyUpOrDown
        spriteImage.imageAlignment = .alignCenter
        cards.orientation = .horizontal
        cards.alignment = .top
        cards.distribution = .fillEqually
        cards.spacing = 14
        spriteImage.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spriteImage.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        loading.orientation = .horizontal
        loading.alignment = .centerY
        loading.spacing = 9
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        loading.addArrangedSubview(spinner)
        loading.addArrangedSubview(loadingLabel)
        loadingLabel.textColor = .secondaryLabelColor
        cards.isHidden = true
    }

    private func installSubviews() {
        [cards, loading, postTitle, xRow].forEach(addSubview)
        xRow.addSubview(xIdentity)
        for item in [cards, loading, postTitle, xRow, xIdentity, xMark, xLabel] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
    }

    private func installActions() {
        movieCopyButton.target = self
        movieCopyButton.action = #selector(copyMovie)
        spriteCopyButton.target = self
        spriteCopyButton.action = #selector(copySprite)
        for view in [xMark, xLabel] {
            view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openX)))
        }
        xMark.setAccessibilityRole(.button)
        xMark.setAccessibilityLabel(localization.string(for: .shareXCreate))
        xLabel.setAccessibilityRole(.button)
    }

    private func installConstraints() {
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 700), heightAnchor.constraint(equalToConstant: 410),
            cards.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            cards.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            cards.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            cards.arrangedSubviews[0].widthAnchor.constraint(equalTo: cards.arrangedSubviews[1].widthAnchor),
            cards.heightAnchor.constraint(equalToConstant: 275),
            loading.centerXAnchor.constraint(equalTo: cards.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: cards.centerYAnchor),
            postTitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            postTitle.topAnchor.constraint(equalTo: cards.bottomAnchor, constant: 17),
            xRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            xRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            xRow.topAnchor.constraint(equalTo: postTitle.bottomAnchor, constant: 7),
            xRow.heightAnchor.constraint(equalToConstant: 52),
            xIdentity.centerXAnchor.constraint(equalTo: xRow.centerXAnchor),
            xIdentity.centerYAnchor.constraint(equalTo: xRow.centerYAnchor),
            xMark.widthAnchor.constraint(equalToConstant: 32),
            xMark.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private static func makeCard(title: String, copyButton: NSButton, preview: NSView, detail: String) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 11
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(calibratedRed: 0.851, green: 0.851, blue: 0.871, alpha: 1).cgColor
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = .secondaryLabelColor
        let surface = CheckerboardView()
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 7
        surface.layer?.masksToBounds = true
        copyButton.isBordered = false
        copyButton.wantsLayer = true
        copyButton.layer?.backgroundColor = NSColor(calibratedRed: 0.929, green: 0.941, blue: 0.957, alpha: 1).cgColor
        copyButton.layer?.cornerRadius = 6
        copyButton.contentTintColor = NSColor(calibratedRed: 0.204, green: 0.224, blue: 0.255, alpha: 1)
        copyButton.font = .systemFont(ofSize: 11)
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageLeading
        [titleLabel, copyButton, surface, detailLabel].forEach(card.addSubview)
        surface.addSubview(preview)
        for item in [titleLabel, copyButton, surface, preview, detailLabel] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -5),
            copyButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -9),
            copyButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            surface.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 9),
            surface.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -9),
            surface.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            surface.heightAnchor.constraint(equalToConstant: 195),
            preview.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            preview.topAnchor.constraint(equalTo: surface.topAnchor),
            preview.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            detailLabel.topAnchor.constraint(equalTo: surface.bottomAnchor, constant: 7),
            detailLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
        ])
        return card
    }
}

@MainActor
private final class ShareXLogoView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        let label = NSAttributedString(
            string: "𝕏",
            attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: NSColor.white]
        )
        let size = label.size()
        label.draw(in: NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        ))
    }
}

@MainActor
private final class ShareXIdentityView: NSStackView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}

@MainActor
private final class CheckerboardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let tile: CGFloat = 14
        let light = NSColor(calibratedWhite: 0.97, alpha: 1)
        let dark = NSColor(calibratedWhite: 0.88, alpha: 1)
        for row in 0 ..< Int(ceil(bounds.height / tile)) {
            for column in 0 ..< Int(ceil(bounds.width / tile)) {
                ((row + column).isMultiple(of: 2) ? light : dark).setFill()
                NSRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile).fill()
            }
        }
    }
}

@MainActor
private final class PetMoviePreviewView: NSView {
    private var playerView: AVPlayerView?
    private let posterView = NSImageView()
    private let playButton = NSButton(title: "▶", target: nil, action: nil)
    private var movieURL: URL?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier(rawValue: "share.moviePreview")
        posterView.imageScaling = .scaleProportionallyUpOrDown
        posterView.imageAlignment = .alignCenter
        posterView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(posterView)
        playButton.title = "▶"
        playButton.isBordered = false
        playButton.wantsLayer = true
        playButton.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 0.88).cgColor
        playButton.layer?.cornerRadius = 20
        playButton.contentTintColor = .white
        playButton.font = .systemFont(ofSize: 17, weight: .semibold)
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

    func stop() {
        player?.pause()
        playerView?.player = nil
        playerView?.removeFromSuperview()
        playerView = nil
        posterView.isHidden = false
        posterView.image = nil
        movieURL = nil
        player = nil
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
            playButton.title = "▶"
        } else {
            if player.currentItem?.currentTime() == player.currentItem?.duration {
                player.seek(to: .zero)
            }
            player.play()
            playButton.title = "Ⅱ"
        }
    }

    private func resetPlayback() {
        player?.pause()
        player?.seek(to: .zero)
        playButton.title = "▶"
    }
}
