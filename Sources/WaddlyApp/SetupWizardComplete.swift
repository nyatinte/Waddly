import SwiftUI
import WaddlyCore

/// The finished step: the outcome, stated as results, and the one hint about what is still
/// changeable. Kept out of `SetupWizardSwiftUI.swift` so each step body stays one screen tall.
@MainActor
extension SetupWizardScreen {
    var monitoringCheckKey: LocalizationKey {
        controller.monitoringCheckKey
    }

    /// The last screen states the outcome instead of asking for anything: the two results share one
    /// card on the page's centered axis, and only the hint about what is still changeable follows.
    var completedPage: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            VStack(spacing: DesignTokens.Spacing.sm) {
                title(.setupCompleteTitle)
                bodyText(.setupCompleteBody)
            }
            .multilineTextAlignment(.center)

            resultCard

            incompleteMonitoringRecovery

            caption(.setupCompleteHint).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Both outcomes in one card: the rows share a left edge inside a surface, so the result reads as
    /// one object instead of two lines floating between centered paragraphs.
    private var resultCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            resultRow(.setupCheckPet, done: true)
            resultRow(monitoringCheckKey, done: controller.isMonitoringReady)
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    /// What to do when the monitoring check did not pass. The warning and its repair belong together,
    /// and the repair differs by why it failed.
    @ViewBuilder private var incompleteMonitoringRecovery: some View {
        if !controller.isMonitoringReady {
            VStack(spacing: DesignTokens.Spacing.sm) {
                caption(controller.monitoringIncompleteWarningKey).multilineTextAlignment(.center)
                if controller.monitoringRecovery == .restart {
                    // The grant is already there; only a fresh process can use it.
                    actionButton(
                        controller.localizedString(.setupRestartNow),
                        identifier: "relaunchApp"
                    ) { controller.relaunchApp() }
                        .buttonStyle(.borderedProminent)
                } else {
                    actionButton(
                        controller.localizedString(controller.monitoringIncompleteActionKey),
                        identifier: "showMonitoringStep"
                    ) { controller.showMonitoringStep() }
                }
            }
        }
    }
}
