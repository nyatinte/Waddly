import AppKit

/// Everything the setup flow needs to know about Input Monitoring.
///
/// The wizard used to own the permission rules, the polling timer, the System Settings URL and the
/// window placement all at once, which is where its recent permission bugs came from. This type
/// owns the rules and the waiting; the wizard only renders `phase` and reacts to `onUpdate`.
///
/// macOS specifics it hides: the grant only applies to a fresh process, and it can arrive at any
/// time while the user is in System Settings, so the app has to keep watching.
@MainActor
final class PermissionService {
    /// What the user is being asked to do right now.
    enum Phase: Equatable {
        case idle
        /// System Settings is open; waiting for the grant.
        case guiding
        /// The guide's fallback: manual steps for adding the app by hand.
        case manual
        /// The user chose "set up later".
        case deferred
    }

    /// How far keyboard reactions have actually progressed on this machine. A live event tap only
    /// proves macOS is delivering *something* to the app, so `isReady` is the last case alone:
    /// a real key has to have reached the app while the tap was running.
    enum Readiness: Equatable {
        /// Input Monitoring has not been granted.
        case permissionMissing
        /// Granted, but macOS has not applied it to a running event tap (a relaunch is needed).
        case tapUnavailable
        /// The tap is live but no key has reached the app yet, so a reaction is unproven.
        case awaitingReaction
        /// A key reached the app while the tap was live: reactions are confirmed.
        case reactionObserved
    }

    private let hasPermission: @MainActor () -> Bool
    private let isReceivingKeys: @MainActor () -> Bool
    /// Whether at least one real key event has reached the app since the tap last started. The app
    /// answers this from the event tap; it never exposes any key code, text, or time.
    private let hasObservedReaction: @MainActor () -> Bool
    private let requestAccess: @MainActor () -> Bool
    private let restartTap: @MainActor () -> Void
    private let openSettings: @MainActor () -> Void
    private let pollInterval: TimeInterval

    private var pollTimer: Timer?

    private(set) var phase = Phase.idle

    /// The permission state changed, or the phase did: re-render.
    var onUpdate: (() -> Void)?
    /// A poll tick while guiding: follow the System Settings window.
    var onTick: (() -> Void)?

    init(
        hasPermission: @escaping @MainActor () -> Bool,
        isReceivingKeys: @escaping @MainActor () -> Bool,
        hasObservedReaction: @escaping @MainActor () -> Bool,
        requestAccess: @escaping @MainActor () -> Bool,
        restartTap: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void = PermissionService.openInputMonitoringSettings,
        pollInterval: TimeInterval = 0.4
    ) {
        self.hasPermission = hasPermission
        self.isReceivingKeys = isReceivingKeys
        self.hasObservedReaction = hasObservedReaction
        self.requestAccess = requestAccess
        self.restartTap = restartTap
        self.openSettings = openSettings
        self.pollInterval = pollInterval
    }

    /// The system has allowed Input Monitoring.
    var isGranted: Bool {
        hasPermission()
    }

    /// The four distinct progress states the guide shows. Only `reactionObserved` is success.
    var readiness: Readiness {
        guard isGranted else { return .permissionMissing }
        guard isReceivingKeys() else { return .tapUnavailable }
        return hasObservedReaction() ? .reactionObserved : .awaitingReaction
    }

    /// Granted *and* a real key has reached the app. A live tap alone is not enough.
    var isReady: Bool {
        readiness == .reactionObserved
    }

    /// The guide is on screen and waiting for the grant. Both presentations count: the drag route
    /// and the manual steps are the same wait, and only the rendering differs.
    var isGuiding: Bool {
        phase == .guiding || phase == .manual
    }

    /// The guide's fallback presentation: add Waddly to the list by hand.
    var isShowingManualSteps: Bool {
        phase == .manual
    }

    var didDefer: Bool {
        phase == .deferred
    }

    // MARK: - Flow

    /// First attempt: ask macOS, and start guiding only if that was not enough.
    func request() {
        guard !isGranted else {
            // Already allowed, so another trip to System Settings would only loop the user back.
            retryTap()
            return
        }
        _ = requestAccess()
        guard isGranted else {
            beginGuiding()
            return
        }
        // The grant arrived without a relaunch: bring the tap up and let the step report whether a
        // real key has reached the app yet. A live tap is not a confirmed reaction.
        retryTap()
    }

    func beginGuiding() {
        phase = .guiding
        openSettings()
        startPolling()
        onUpdate?()
    }

    func toggleManualSteps() {
        phase = isShowingManualSteps ? .guiding : .manual
        if phase == .guiding {
            startPolling()
            openSettings()
        }
        onUpdate?()
    }

    func deferSetup() {
        phase = .deferred
        stopPolling()
        onUpdate?()
    }

    /// Granted but not receiving: restart the tap. Never reopen System Settings here.
    func retryTap() {
        restartTap()
        onUpdate?()
    }

    /// Re-read the permission state, finishing the guide if the grant arrived.
    func refresh() {
        guard isGranted, isGuiding else { return }
        finishGrantedGuide()
    }

    /// One polling step. Internal so tests can drive it without waiting on a timer.
    func tick() {
        guard isGuiding else { return }
        guard !isGranted else {
            finishGrantedGuide()
            return
        }
        onTick?()
    }

    func stop() {
        stopPolling()
    }

    private func finishGuiding() {
        stopPolling()
        phase = .idle
        onUpdate?()
    }

    /// The grant landed while the guide was watching. macOS only applies it to a *new* event tap, so
    /// the tap is restarted before the guide repaints: otherwise the step reads granted-but-not-
    /// receiving and tells the user to restart the app for a tap that was never started.
    private func finishGrantedGuide() {
        restartTap()
        finishGuiding()
    }

    private func startPolling() {
        stopPolling()
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = pollInterval * 0.25
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Opened without any extra permission: `x-apple.systempreferences` deep links are public.
    static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
