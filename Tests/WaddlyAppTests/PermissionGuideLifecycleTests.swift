import AppKit
import Testing
@testable import WaddlyApp

@Suite(.serialized) @MainActor struct PermissionGuideLifecycleTests {
    @Test func movingTheCompanionStopsFollowingEvenWhenShownAgain() throws {
        let wizard = try SetupWizardFixture.makeWizard(granted: true, isMonitoringSettings: true)
        let guide = PermissionGuidePanelController(wizard: wizard)
        let panel = try #require(guide.window)
        panel.alphaValue = 0
        defer {
            guide.stop()
            wizard.close()
        }
        guide.show()
        #expect(guide.isFollowingSystemSettings)
        panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x + 50, y: panel.frame.origin.y))
        guide.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        #expect(!guide.isFollowingSystemSettings)
        let moved = panel.frame.origin
        guide.show()
        #expect(!guide.isFollowingSystemSettings)
        #expect(panel.frame.origin == moved)
    }
}
