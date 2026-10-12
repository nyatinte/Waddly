import AppKit
import Testing
@testable import WaddlyApp

/// The permission rules were the source of every recent setup bug, so they get their own suite.
/// These tests drive the state machine directly; no window, no System Settings, no real timer.
@Suite(.serialized) @MainActor struct PermissionServiceTests {
    @Test func askingWhileUnauthorisedOpensSettingsAndWaits() {
        let fake = Fake()
        let service = fake.makeService()
        var updates = 0
        service.onUpdate = { updates += 1 }

        service.request()

        #expect(service.phase == .guiding)
        #expect(service.isGuiding)
        #expect(fake.settingsOpened == 1)
        #expect(fake.tapRestarts == 0)
        #expect(updates == 1)
    }

    /// Reopening System Settings when the permission is already granted would loop the user.
    @Test func askingWhileAlreadyGrantedOnlyRestartsTheTap() {
        let fake = Fake()
        fake.granted = true
        let service = fake.makeService()

        service.request()

        #expect(service.phase == .idle)
        #expect(fake.settingsOpened == 0)
        #expect(fake.tapRestarts == 1)
    }

    @Test func grantedButNotReceivingIsNotReady() {
        let fake = Fake()
        fake.granted = true
        fake.receivingKeys = false
        let service = fake.makeService()

        #expect(service.isGranted)
        #expect(!service.isReady)

        fake.receivingKeys = true
        #expect(service.isReady)
    }

    @Test func aTickWhileWaitingFollowsTheSettingsWindow() {
        let fake = Fake()
        let service = fake.makeService()
        var ticks = 0
        service.onTick = { ticks += 1 }
        service.request()

        service.tick()

        #expect(ticks == 1)
        #expect(service.phase == .guiding)
    }

    @Test func theGrantArrivingEndsTheGuide() {
        let fake = Fake()
        let service = fake.makeService()
        var updates = 0
        service.onUpdate = { updates += 1 }
        service.request()

        fake.granted = true
        service.tick()

        #expect(service.phase == .idle)
        #expect(!service.isGuiding)
        #expect(updates == 2)
    }

    @Test func refreshEndsTheGuideWhenTheGrantArrivedWhileAway() {
        let fake = Fake()
        let service = fake.makeService()
        service.request()

        // The user granted while the app was inactive, so no tick ran.
        fake.granted = true
        service.refresh()

        #expect(service.phase == .idle)
    }

    @Test func manualStepsToggleBackToTheDragGuide() {
        let fake = Fake()
        let service = fake.makeService()
        service.request()

        service.toggleManualSteps()
        #expect(service.phase == .manual)
        #expect(service.isShowingManualSteps)
        // The manual steps are still the guide: the window keeps floating and keeps watching.
        #expect(service.isGuiding)

        service.toggleManualSteps()
        #expect(service.phase == .guiding)
        // Going back to the drag route reopens the pane it points at.
        #expect(fake.settingsOpened == 2)
    }

    /// The manual steps are instructions to follow elsewhere, so the guide has to keep watching:
    /// the user adds the app by hand and macOS grants it while this page is still on screen.
    @Test func theManualStepsKeepWaitingForTheGrant() {
        let fake = Fake()
        let service = fake.makeService()
        service.request()
        service.toggleManualSteps()

        var ticks = 0
        service.onTick = { ticks += 1 }
        service.tick()
        #expect(ticks == 1)

        fake.granted = true
        service.tick()
        #expect(service.phase == .idle)
        #expect(!service.isGuiding)
    }

    @Test func deferringIsRemembered() {
        let fake = Fake()
        let service = fake.makeService()
        service.request()

        service.deferSetup()

        #expect(service.phase == .deferred)
        #expect(service.didDefer)
        #expect(!service.isGuiding)
    }

    /// Polling has to actually run: the grant can arrive at any moment while System Settings is open.
    @Test func pollingKeepsCheckingUntilGranted() async throws {
        let fake = Fake()
        let service = fake.makeService(pollInterval: 0.05)
        defer { service.stop() }
        service.request()
        #expect(service.phase == .guiding)

        fake.granted = true
        try await waitUntil(timeout: .seconds(3)) { service.phase == .idle }

        #expect(service.phase == .idle)
    }

    @Test func stoppingEndsThePolling() async throws {
        let fake = Fake()
        let service = fake.makeService(pollInterval: 0.05)
        defer { service.stop() }
        service.request()

        var ticks = 0
        service.onTick = { ticks += 1 }
        // A busy main actor can delay a Timer well past its interval, so wait for the first tick
        // instead of assuming it lands within a fixed window.
        try await waitUntil(timeout: .seconds(3)) { ticks > 0 }
        #expect(ticks > 0)

        service.stop()
        let afterStop = ticks
        try await Task.sleep(for: .milliseconds(300))
        #expect(ticks == afterStop)
    }

    /// Yields to the main actor while waiting, so the timer can actually fire.
    private func waitUntil(
        timeout: Duration,
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("timed out waiting for the condition")
    }

    @MainActor
    private final class Fake {
        var granted = false
        var receivingKeys = true
        var settingsOpened = 0
        var tapRestarts = 0

        func makeService(pollInterval: TimeInterval = 60) -> PermissionService {
            PermissionService(
                hasPermission: { self.granted },
                isReceivingKeys: { self.receivingKeys },
                requestAccess: { self.granted },
                restartTap: { self.tapRestarts += 1 },
                openSettings: { self.settingsOpened += 1 },
                pollInterval: pollInterval
            )
        }
    }
}
