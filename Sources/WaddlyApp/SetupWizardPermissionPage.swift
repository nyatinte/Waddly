import AppKit
import SwiftUI

/// The Keyboard reactions step, which is also the Input Monitoring settings screen.
///
/// It lives apart from the character pages because it changes most often: one state per permission
/// readiness, one instruction card per route, and one primary action on each. The shared pieces —
/// `pageHeader`, `cardContainer`, `numberedStep`, `permissionActions` — come from
/// `SetupWizardSwiftUIComponents.swift`, so a new state is a stack of existing parts.
@MainActor
extension SetupWizardScreen {
    var monitoringPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch controller.monitoringReadiness {
            case .permissionMissing:
                missingPermissionContent
            case .tapUnavailable:
                restartRequiredContent
            case .awaitingReaction:
                awaitingReactionContent
            case .reactionObserved:
                readyMonitoringContent
            }
        }
    }

    /// The tap is live but no key has reached the app yet: the pet is awake, reactions are unproven.
    private var awaitingReactionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader(.setupMonitoringWaitingTitle, statusKey: .setupMonitoringStatusWaiting, positive: false)
            bodyText(.setupMonitoringWaitingBody)
            bodyText(.setupTryTyping)
            actionButton(
                controller.localizedString(.setupNotWorking),
                identifier: "toggleTroubleshooting"
            ) { controller.toggleTroubleshooting() }
            if controller.isShowingTroubleshooting {
                troubleshootingContent
            }
        }
    }

    private var readyMonitoringContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader(.setupMonitoringGrantedTitle, statusKey: .setupMonitoringStatusGranted, positive: true)
            bodyText(.setupMonitoringGrantedBody)
            bodyText(.setupTryTyping)
            actionButton(
                controller.localizedString(.setupNotWorking),
                identifier: "toggleTroubleshooting"
            ) { controller.toggleTroubleshooting() }
            if controller.isShowingTroubleshooting {
                troubleshootingContent
            }
        }
    }

    private var troubleshootingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(.setupTroubleshootingTitle)
            bodyText(.setupTroubleshootingBody)
            actionButton(
                controller.localizedString(.setupRestartNow),
                identifier: "relaunchApp"
            ) { controller.relaunchApp() }
            actionButton(
                controller.localizedString(.setupRevealInFinder),
                identifier: "revealInFinder"
            ) { controller.revealInFinder() }
            actionButton(
                controller.localizedString(.setupOpenSystemSettings),
                identifier: "openInputMonitoringSettings"
            ) { controller.openInputMonitoringSettings() }
        }
    }

    private var restartRequiredContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader(.setupRestartRequiredTitle, statusKey: .setupMonitoringStatusGranted, positive: true)
            bodyText(.setupRestartRequiredBody)
            primaryActionButton(
                controller.localizedString(.setupRestartNow),
                identifier: "relaunchApp"
            ) { controller.relaunchApp() }
            actionButton(
                controller.localizedString(.setupRetryWithoutRestart),
                identifier: "retryMonitoring"
            ) { controller.retryMonitoring() }
            actionButton(
                controller.localizedString(.setupRevealInFinder),
                identifier: "revealInFinder"
            ) { controller.revealInFinder() }
        }
    }

    private var missingPermissionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader(.setupMonitoringTitle, statusKey: .setupMonitoringStatusOff, positive: false)
            bodyText(.setupMonitoringBody)
            permissionActionContent
            privacyFootnote
        }
    }

    /// Two routes out of "not allowed": ask macOS, or add Waddly by hand once macOS has stopped
    /// asking. Each route is one instruction card ending in one primary action plus one alternative.
    @ViewBuilder private var permissionActionContent: some View {
        if controller.isShowingManualSteps {
            cardContainer {
                numberedSteps([.setupManualStep1, .setupManualStep2, .setupManualStep3])
                permissionActions(
                    primary: SetupAction(
                        title: .setupOpenSystemSettings,
                        identifier: "openInputMonitoringSettings"
                    ) { controller.openInputMonitoringSettings() },
                    alternative: SetupAction(
                        title: .setupDragInstead,
                        identifier: "dragInstead"
                    ) { controller.toggleManualSteps() }
                )
                caption(.setupMonitoringWatching)
            }
        } else if controller.isShowingGuide {
            cardContainer {
                numberedStep(1, .setupManualStep1)
                dragStep
                permissionActions(
                    primary: SetupAction(
                        title: .setupOpenSystemSettings,
                        identifier: "reopenSettings"
                    ) { controller.openInputMonitoringSettings() },
                    alternative: SetupAction(
                        title: .setupHelperAlternative,
                        identifier: "helperAlternative"
                    ) { controller.toggleManualSteps() }
                )
                caption(.setupMonitoringWatching)
            }
        } else {
            primaryActionButton(
                controller.localizedString(.setupEnableMonitoring),
                identifier: "enableMonitoring"
            ) { controller.enableMonitoring() }
        }
    }

    /// Step 2 is the drag itself, so the icon the step names sits inside that step instead of in a
    /// separate box the user has to connect to the instruction.
    private var dragStep: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.actionGap) {
            stepBadge(2)
            AppIconDragSource(localization: controller.localization)
                .frame(width: 36, height: 36)
            Text(controller.localizedString(.setupDropGuideBody))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// The privacy promise holds for every permission state. As a footnote it no longer takes the
    /// place under the title that the instruction needs.
    private var privacyFootnote: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.actionGap) {
            Image(systemName: "lock.shield").font(.caption)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(controller.localizedString(.setupPrivacyTitle)).font(.caption.weight(.semibold))
                Text(controller.localizedString(.setupPrivacyNote)).font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// The draggable Waddly icon, in the page column. Reuses the AppKit drag source so the pasteboard
/// item keeps the file-URL flavours System Settings accepts.
@MainActor
private struct AppIconDragSource: NSViewRepresentable {
    let localization: LocalizationController

    func makeNSView(context: Context) -> DraggableAppIconView {
        DraggableAppIconView(localization: localization)
    }

    func updateNSView(_ nsView: DraggableAppIconView, context: Context) {
        nsView.updateLocalization(localization)
    }
}
