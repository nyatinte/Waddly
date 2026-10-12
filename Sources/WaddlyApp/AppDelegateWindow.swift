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
            panel.orderFrontRegardless()
        }
    }

    func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        let frame = NSRect(origin: origin, size: panel.frame.size)
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return origin }
        let maxX = max(visible.minX, visible.maxX - frame.width)
        let maxY = max(visible.minY, visible.maxY - frame.height)
        return NSPoint(x: min(max(origin.x, visible.minX), maxX), y: min(max(origin.y, visible.minY), maxY))
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
            panel.orderFrontRegardless()
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            // The handler is not main-actor isolated, so hop back before touching the panel.
            Task { @MainActor in
                self?.panel.alphaValue = 1
            }
        }
    }

    private func placeAtDefaultPosition() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(x: visible.maxX - panel.frame.width - 18, y: visible.minY + 18)
        panel.setFrameOrigin(origin)
        saveOrigin()
    }
}
