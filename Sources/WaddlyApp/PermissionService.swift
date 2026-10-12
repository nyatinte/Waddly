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

    private let hasPermission: @MainActor () -> Bool
    private let isReceivingKeys: @MainActor () -> Bool
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
        requestAccess: @escaping @MainActor () -> Bool,
        restartTap: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void = PermissionService.openInputMonitoringSettings,
        pollInterval: TimeInterval = 0.4
    ) {
        self.hasPermission = hasPermission
        self.isReceivingKeys = isReceivingKeys
        self.requestAccess = requestAccess
        self.restartTap = restartTap
        self.openSettings = openSettings
        self.pollInterval = pollInterval
    }

    /// The system has allowed Input Monitoring.
    var isGranted: Bool {
        hasPermission()
    }

    /// Granted *and* the keyboard is actually arriving. Only this counts as ready.
    var isReady: Bool {
        isGranted && isReceivingKeys()
    }

    var isGuiding: Bool {
        phase == .guiding
    }

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
        guard !isReady else {
            onUpdate?()
            return
        }
        beginGuiding()
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
        guard isGranted, phase == .guiding || phase == .manual else { return }
        finishGuiding()
    }

    /// One polling step. Internal so tests can drive it without waiting on a timer.
    func tick() {
        guard phase == .guiding else { return }
        guard !isGranted else {
            finishGuiding()
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
