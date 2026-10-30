import AppKit
import SwiftUI

/// The Keyboard reactions step, which is also the Input Monitoring settings screen.
///
/// It lives apart from the character pages because it changes most often: one state per permission
/// readiness, and one primary action. The guide itself is three step cards: add Waddly, turn it
/// on, then restart. Shared pieces — `pageHeader`, `cardContainer`, `stepBadge` — come from
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            if controller.isShowingGuide {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    title(.setupMonitoringTitle)
                    bodyText(.setupGuideIntro)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                guideSteps
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

    private var permissionActionContent: some View {
        primaryActionButton(
            controller.localizedString(.setupEnableMonitoring),
            identifier: "enableMonitoring"
        ) { controller.enableMonitoring() }
    }

    private var guideSteps: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            addToListStep
            turnOnStep
            restartStep
        }
    }

    /// Tighter than the shared card so the three steps fit the compact guide without clipping.
    private func guideCard(@ViewBuilder _ content: () -> some View) -> some View {
        cardContainer(spacing: DesignTokens.Spacing.sm, padding: DesignTokens.Spacing.sm) {
            content()
        }
    }

    private var addToListStep: some View {
        guideCard {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                stepBadge(1)
                AppIconDragSource(localization: controller.localization)
                    .frame(width: DesignTokens.Control.dragIconSize, height: DesignTokens.Control.dragIconSize)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    guideStepTitle(1, .setupGuideAddTitle)
                    guideStepDetail(.setupGuideAddBody)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer(minLength: 0)
                openSettingsButton
            }
        }
    }

    private var turnOnStep: some View {
        guideCard {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                stepBadge(2)
                guideIconSlot {
                    GuideToggle(isOn: true)
                        .frame(
                            width: DesignTokens.Spacing.xxxl + DesignTokens.Spacing.lg,
                            height: DesignTokens.Spacing.xl + DesignTokens.Spacing.xs
                        )
                }
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    guideStepTitle(2, .setupGuideTurnOnTitle)
                    guideStepDetail(.setupGuideTurnOnBody)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                InputMonitoringIllustration(
                    title: controller.localizedString(.setupGuidePreviewInputMonitoring),
                    appName: guideAppName,
                    otherApps: controller.localizedString(.setupGuidePreviewOtherApps)
                )
            }
        }
    }

    private var restartStep: some View {
        guideCard {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                stepBadge(3)
                guideIconSlot {
                    Image(systemName: "arrow.clockwise")
                        .resizable()
                        .scaledToFit()
                        .frame(width: DesignTokens.Spacing.xxxl, height: DesignTokens.Spacing.xxxl)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    guideStepTitle(3, .setupGuideRestartTitle)
                    guideStepDetail(.setupGuideRestartBody)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RestartPromptIllustration(
                    appName: guideAppName,
                    reopen: controller.localizedString(.setupGuidePreviewQuitAndReopen),
                    quit: controller.localizedString(.setupGuidePreviewQuit)
                )
            }
        }
    }

    private var openSettingsButton: some View {
        primaryActionButton(
            controller.localizedString(.setupOpenSystemSettings),
            identifier: "reopenSettings",
            systemImage: "arrow.up.forward.square"
        ) { controller.openInputMonitoringSettings() }
    }

    private var guideAppName: String {
        "Waddly"
    }

    private func guideStepTitle(_ index: Int, _ key: LocalizationKey) -> some View {
        Text(controller.localizedString(key))
            .font(DesignTokens.Typography.heading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(stepAccessibilityLabel(index, key))
    }

    private func guideStepDetail(_ key: LocalizationKey) -> some View {
        Text(controller.localizedString(key))
            .font(DesignTokens.Typography.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func guideIconSlot(@ViewBuilder _ icon: () -> some View) -> some View {
        icon()
            .frame(width: DesignTokens.Control.dragIconSize, height: DesignTokens.Control.dragIconSize)
            .accessibilityHidden(true)
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

/// A picture of the Input Monitoring list, so the turn-on step shows the switch the user will see.
private struct InputMonitoringIllustration: View {
    let title: String
    let appName: String
    let otherApps: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
                Text(title)
            }
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(.secondary)
            illustrationRow(appIcon: true, title: appName, isOn: true)
            illustrationRow(appIcon: false, title: otherApps, isOn: false)
        }
        .padding(DesignTokens.Spacing.sm)
        .fixedSize(horizontal: true, vertical: true)
        .background(illustrationShape, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.surface))
        .overlay(illustrationStroke)
        .accessibilityHidden(true)
    }

    private func illustrationRow(appIcon: Bool, title: String, isOn: Bool) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if appIcon {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .frame(width: DesignTokens.Spacing.xl, height: DesignTokens.Spacing.xl)
            } else {
                Image(systemName: "app")
                    .font(DesignTokens.Typography.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: DesignTokens.Spacing.xl, height: DesignTokens.Spacing.xl)
            }
            Text(title)
                .font(DesignTokens.Typography.caption)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            GuideToggle(isOn: isOn)
        }
    }
}

/// A picture of the quit prompt macOS shows after Input Monitoring is turned on.
private struct RestartPromptIllustration: View {
    let appName: String
    let reopen: String
    let quit: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(appName)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.bottom, DesignTokens.Spacing.xxs)
            Text(reopen)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(Color(nsColor: .selectedMenuItemTextColor))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(nsColor: .selectedContentBackgroundColor),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                )
            Text(quit)
                .font(DesignTokens.Typography.caption)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .padding(DesignTokens.Spacing.sm)
        .fixedSize(horizontal: true, vertical: true)
        .background(illustrationShape, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.surface))
        .overlay(illustrationStroke)
        .accessibilityHidden(true)
    }
}

/// Decorative switch. Not a control: the step text is what the user acts on.
private struct GuideToggle: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : Color(nsColor: .disabledControlTextColor))
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .padding(DesignTokens.Spacing.xxs)
            }
            .frame(
                width: DesignTokens.Spacing.xxl + DesignTokens.Spacing.sm,
                height: DesignTokens.Spacing.lg
            )
    }
}

private var illustrationShape: Color {
    Color(nsColor: .windowBackgroundColor)
}

private var illustrationStroke: some View {
    RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
        .stroke(Color(nsColor: .separatorColor))
}
