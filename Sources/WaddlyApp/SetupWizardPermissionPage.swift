import AppKit
import SwiftUI

/// The Keyboard reactions step, which is also the Input Monitoring settings screen.
///
/// It lives apart from the character pages because it changes most often: one state per permission
/// readiness, and one primary action. While guiding, the drag source is the hero: the icon, a
/// direction cue, and a picture of Input Monitoring. Shared pieces come from
/// `SetupWizardSwiftUIComponents.swift`.
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
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer(minLength: 0)
            AppIconDragSource(localization: controller.localization)
                .frame(width: 112, height: 112)
                .accessibilityLabel(controller.localizedString(.setupDragAppIcon))
            title(.setupGuideTitle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            bodyText(.setupGuideIntro)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            primaryActionButton(
                controller.localizedString(.setupOpenSystemSettings),
                identifier: "enableMonitoring",
                systemImage: "gearshape"
            ) { controller.showPermissionGuide() }
            caption(.setupGuideDragFallback)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DesignTokens.Spacing.xl)
    }
}

/// The draggable Waddly icon, in the page column. Reuses the AppKit drag source so the pasteboard
/// item keeps the file-URL flavours System Settings accepts.
@MainActor
struct AppIconDragSource: NSViewRepresentable {
    let localization: LocalizationController
    var onViewCreated: (DraggableAppIconView) -> Void = { _ in }
    var onDragStarted: () -> Void = {}

    func makeNSView(context: Context) -> DraggableAppIconView {
        let view = DraggableAppIconView(localization: localization)
        onViewCreated(view)
        view.onDragStarted = onDragStarted
        return view
    }

    func updateNSView(_ nsView: DraggableAppIconView, context: Context) {
        nsView.updateLocalization(localization)
        nsView.onDragStarted = onDragStarted
    }
}
