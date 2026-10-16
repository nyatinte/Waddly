import AppKit
import WaddlyCore

extension AppDelegate {
    func setDockVisibility(_ visible: Bool) {
        guard visible || canToggleDock(
            showInDock: settings.showInDock,
            showInMenuBar: settings.showInMenuBar
        ) else { return }
        settings.showInDock = visible
        updatePresenceOptions()
    }

    func setMenuBarVisibility(_ visible: Bool) {
        guard visible || canToggleMenuBar(
            showInDock: settings.showInDock,
            showInMenuBar: settings.showInMenuBar
        ) else { return }
        settings.showInMenuBar = visible
        updatePresenceOptions()
    }

    func setDisplaySize(_ size: CGFloat) {
        settings.displaySize = size
        panel.setContentSize(NSSize(width: size, height: size))
        petView.frame = panel.contentView?.bounds ?? .zero
        panel.setFrameOrigin(clampedOrigin(panel.frame.origin))
        synchronizeMenuSelection(in: [statusMenu], action: NSSelectorFromString("setSize:"), selectedTag: Int(size))
        saveOrigin()
    }

    func applyTypingMotion(_ motion: TypingMotion) {
        settings.typingMotion = motion
        synchronizeMenuSelection(
            in: [statusMenu],
            action: NSSelectorFromString("setTypingMotion:"),
            selectedTag: motion.rawValue
        )
        animationController.typingMotionDidChange(motion)
    }

    func setBreathingEnabled(_ enabled: Bool) {
        settings.breathingEnabled = enabled
        breathingItem.state = enabled ? .on : .off
        animationController.breathingPreferenceDidChange()
    }
}
