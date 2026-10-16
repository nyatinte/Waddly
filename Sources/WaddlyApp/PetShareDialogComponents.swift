import AppKit
import AVKit

@MainActor
final class ShareXLogoView: NSView {
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
final class ShareXIdentityView: NSStackView {
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

@MainActor
final class PetMoviePreviewView: NSView {
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
