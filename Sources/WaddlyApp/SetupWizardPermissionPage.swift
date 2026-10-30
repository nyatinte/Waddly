import AppKit
import SwiftUI

/// The Keyboard reactions step, which is also the Input Monitoring settings screen.
///
/// It lives apart from the character pages because it changes most often: one state per permission
/// readiness, one instruction card per route, and one primary action on each. The shared pieces —
/// `pageHeader`, `cardContainer`, `numberedStep` — come from
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
            bodyText(.setupTroubleshootingBody)
            actionButton(
                controller.localizedString(.setupRestartNow),
                identifier: "relaunchApp"
            ) { controller.relaunchApp() }
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
            // Restarting is the documented remedy, but a grant macOS recorded against an older build
            // of the app cannot be applied by any restart. Re-opening System Settings is the only way
            // out of that state: toggling the switch off and on records the current build.
            actionButton(
                controller.localizedString(.setupOpenSystemSettings),
                identifier: "openInputMonitoringSettings"
            ) { controller.openInputMonitoringSettings() }
            actionButton(
                controller.localizedString(.setupRevealInFinder),
                identifier: "revealInFinder"
            ) { controller.revealInFinder() }
        }
    }

    private var missingPermissionContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            if controller.isShowingGuide {
                pageHeader(.setupMonitoringTitle, statusKey: .setupMonitoringStatusOff, positive: false)
                permissionActionContent
            } else {
                title(.setupMonitoringTitle)
                cardContainer {
                    status(.setupMonitoringStatusOff, positive: false)
                    bodyText(.setupMonitoringBody)
                    permissionActionContent
                    caption(.setupMonitoringActionHint)
                }
            }
            privacyFootnote
        }
    }

    @ViewBuilder private var permissionActionContent: some View {
        if controller.isShowingGuide {
            cardContainer {
                dragStep
                numberedStep(2, .setupManualStep3)
                numberedStep(3, .setupRestartPromptStep)
                primaryActionButton(
                    controller.localizedString(.setupOpenSystemSettings),
                    identifier: "reopenSettings"
                ) { controller.openInputMonitoringSettings() }
            }
        } else {
            primaryActionButton(
                controller.localizedString(.setupEnableMonitoring),
                identifier: "enableMonitoring"
            ) { controller.enableMonitoring() }
        }
    }

    private var dragStep: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.actionGap) {
            stepBadge(1)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(controller.localizedString(.setupDropGuideBody))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(stepAccessibilityLabel(1, .setupDropGuideBody))
                caption(.setupDragAlternative)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DesignTokens.Spacing.sm) {
                AppIconDragSource(localization: controller.localization)
                    .frame(width: DesignTokens.Control.dragIconSize, height: DesignTokens.Control.dragIconSize)
                Image(systemName: "arrow.right")
                    .font(DesignTokens.Typography.heading)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var privacyFootnote: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.actionGap) {
            Image(systemName: "lock.shield").font(DesignTokens.Typography.callout)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(controller.localizedString(.setupPrivacyTitle)).font(DesignTokens.Typography.heading)
                Text(controller.localizedString(.setupPrivacyNote)).font(DesignTokens.Typography.callout)
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
