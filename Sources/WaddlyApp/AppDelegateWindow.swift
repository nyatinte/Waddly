import AppKit
import WaddlyCore

extension NSWindow {
    var isUsingDarkAppearance: Bool {
        switch effectiveAppearance.name {
        case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
            true
        default:
            false
        }
    }
}

extension AppDelegate {
    func buildPanel() {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.delegate = self

        petView.image = petImages[.idle].first
        petView.imageScaling = .scaleProportionallyUpOrDown
        petView.wantsLayer = true
        petView.autoresizingMask = [.width, .height]
        panel.contentView = petView

        if let saved = settings.panelOrigin, saved.count == 2 {
            panel.setFrameOrigin(clampedOrigin(NSPoint(x: saved[0], y: saved[1])))
        } else {
            placeAtDefaultPosition()
        }
        if hasCompletePetImageSet {
            presenter.reveal(panel)
        }
    }

    func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        PetWindowPlacement.clampedOrigin(
            origin,
            size: panel.frame.size,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            mainVisibleFrame: NSScreen.main?.visibleFrame
        )
    }

    /// Pulls the pet back onto a screen that still exists after the display configuration changes.
    @objc func screenParametersDidChange(_ notification: Notification) {
        panel.setFrameOrigin(clampedOrigin(panel.frame.origin))
        saveOrigin()
    }

    func saveOrigin() {
        let origin = panel.frame.origin
        settings.panelOrigin = [origin.x, origin.y]
    }

    /// Fades the pet in when setup hands it over, so the first appearance reads as an arrival.
    func revealPetOnDesktop() {
        guard hasCompletePetImageSet else { return }
        // Reduced motion, or any interrupted animation, must never leave the pet invisible.
        guard !MotionPreference.isReduced else {
            panel.alphaValue = 1
            presenter.reveal(panel)
            return
        }
        presenter.revealFadingIn(panel, 0.4)
    }

    private func placeAtDefaultPosition() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(x: visible.maxX - panel.frame.width - 18, y: visible.minY + 18)
        panel.setFrameOrigin(origin)
        saveOrigin()
    }
}
