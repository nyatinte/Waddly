import AppKit
import WaddlyCore

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

        petView.image = petImages[.idle][0]
        petView.imageScaling = .scaleProportionallyUpOrDown
        petView.wantsLayer = true
        petView.autoresizingMask = [.width, .height]
        panel.contentView = petView

        if let saved = defaults.array(forKey: "panelOrigin") as? [Double], saved.count == 2 {
            panel.setFrameOrigin(clampedOrigin(NSPoint(x: saved[0], y: saved[1])))
        } else {
            placeAtDefaultPosition()
        }
        panel.orderFrontRegardless()
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
        defaults.set([origin.x, origin.y], forKey: "panelOrigin")
    }

    private func placeAtDefaultPosition() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(x: visible.maxX - panel.frame.width - 18, y: visible.minY + 18)
        panel.setFrameOrigin(origin)
        saveOrigin()
    }
}
