/// What the completion page says and offers for each monitoring readiness state. Kept out of the
/// controller's main body so the step logic and the recovery copy stay separately readable.
extension SetupWizardController {
    /// The completion page states the monitoring outcome truthfully for each readiness state.
    var monitoringCheckKey: LocalizationKey {
        switch monitoringReadiness {
        case .reactionObserved: .setupCheckMonitoring
        case .awaitingReaction: .setupCheckMonitoringWaiting
        case .tapUnavailable: .setupCheckMonitoringRestart
        case .permissionMissing: .setupCheckMonitoringOff
        }
    }

    /// How the completion page repairs an incomplete monitoring check. A granted permission with an
    /// unavailable tap is its own case: sending the user back to "enable" would be a lie, because
    /// only a restart can apply it.
    enum MonitoringRecovery: Equatable {
        case restart
        case confirmTyping
        case setUpMonitoring
    }

    var monitoringRecovery: MonitoringRecovery {
        switch monitoringReadiness {
        case .tapUnavailable: .restart
        case .awaitingReaction: .confirmTyping
        case .permissionMissing, .reactionObserved: .setUpMonitoring
        }
    }

    /// The completion page's warning when the monitoring check is incomplete.
    var monitoringIncompleteWarningKey: LocalizationKey {
        switch monitoringRecovery {
        case .restart: .setupCompleteWarningRestart
        case .confirmTyping: .setupCompleteWarningWaiting
        case .setUpMonitoring: .setupCompleteWarning
        }
    }

    /// What the completion page offers next: restart when the grant needs a fresh process, confirm
    /// by typing when the tap is already live, otherwise send the user back to set Input Monitoring up.
    var monitoringIncompleteActionKey: LocalizationKey {
        switch monitoringRecovery {
        case .restart: .setupRestartNow
        case .confirmTyping: .setupConfirmTyping
        case .setUpMonitoring: .setupSetUpMonitoring
        }
    }
}
