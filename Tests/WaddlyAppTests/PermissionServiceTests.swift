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

    /// A live tap is not proof by itself: macOS can deliver a running tap while no key ever reaches
    /// the app, so the reaction has to be observed before setup can call itself ready.
    @Test func aLiveTapWithoutADeliveredKeyIsAwaitingReaction() {
        let fake = Fake()
        fake.granted = true
        fake.receivingKeys = true
        fake.observedReaction = false
        let service = fake.makeService()

        #expect(service.isGranted)
        #expect(service.readiness == .awaitingReaction)
        #expect(!service.isReady)

        fake.observedReaction = true
        #expect(service.readiness == .reactionObserved)
        #expect(service.isReady)
    }

    @Test func readinessSeparatesMissingPermissionFromAnUnavailableTap() {
        let denied = Fake()
        #expect(denied.makeService().readiness == .permissionMissing)

        let unavailable = Fake()
        unavailable.granted = true
        unavailable.receivingKeys = false
        #expect(unavailable.makeService().readiness == .tapUnavailable)
    }

    /// "Set up later" is an explicit escape, not a confirmation: the reaction stays unproven.
    @Test func deferringDoesNotConfirmReactions() {
        let fake = Fake()
        fake.granted = true
        fake.receivingKeys = true
        fake.observedReaction = false
        let service = fake.makeService()

        service.deferSetup()

        #expect(service.phase == .deferred)
        #expect(service.readiness == .awaitingReaction)
        #expect(!service.isReady)
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

    /// The grant ends the guide *and* starts a fresh tap: macOS only applies Input Monitoring to a
    /// new tap, so repainting before restarting it would tell the user to restart the app instead.
    @Test func theGrantArrivingEndsTheGuideAndRestartsTheTap() {
        let fake = Fake()
        let service = fake.makeService()
        var updates = 0
        service.onUpdate = { updates += 1 }
        service.request()

        fake.granted = true
        service.tick()

        #expect(service.phase == .idle)
        #expect(!service.isGuiding)
        #expect(fake.tapRestarts == 1)
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
        #expect(fake.tapRestarts == 1)
    }

    /// The guide keeps watching whether the user adds the app by dragging or using +.
    @Test func theGuideKeepsWaitingForTheGrant() {
        let fake = Fake()
        let service = fake.makeService()
        service.request()

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
        /// A delivered key. `false` with a live tap models "running but nothing has arrived yet".
        var observedReaction = true
        var settingsOpened = 0
        var tapRestarts = 0

        func makeService(pollInterval: TimeInterval = 60) -> PermissionService {
            PermissionService(
                hasPermission: { self.granted },
                isReceivingKeys: { self.receivingKeys },
                hasObservedReaction: { self.observedReaction },
                requestAccess: { self.granted },
                restartTap: { self.tapRestarts += 1 },
                openSettings: { self.settingsOpened += 1 },
                pollInterval: pollInterval
            )
        }
    }
}
