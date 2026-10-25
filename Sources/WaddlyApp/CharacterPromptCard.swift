import AppKit
import SwiftUI

/// Always available in Change Character, even when the saved pet occupies the import area.
/// Copying a prompt does not stage or apply an image, and opening a browser is opt-in.
@MainActor
struct CharacterPromptCard: View {
    let localization: LocalizationController
    let pasteboard: NSPasteboard
    var resourcesURL: URL? = Bundle.main.resourceURL
    var openBrowser: @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }
    var announce: @MainActor (String) -> Void = SetupWizardController.postAccessibilityAnnouncement
    // Name the property-wrapper type explicitly; newer SDKs also export a State macro.
    private typealias FeedbackState = SwiftUI.State<SpriteSheetPrompt.Feedback?>
    @FeedbackState private var feedback = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(localization.string(for: .characterPromptTitle))
                .font(DesignTokens.Typography.heading)
            Text(localization.string(for: .characterPromptBody))
                .font(DesignTokens.Typography.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: LayoutMetrics.actionGap) { actions }
                VStack(alignment: .leading, spacing: LayoutMetrics.actionGap) { actions }
            }
            if let feedback {
                Label(
                    localization.string(for: feedback.messageKey),
                    systemImage: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(feedback.isError ? DesignTokens.Status.critical : DesignTokens.Status.positive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("characterPromptFeedback")
            }
        }
        .font(DesignTokens.Typography.action)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card).stroke(Color(nsColor: .separatorColor)))
        .accessibilityIdentifier("characterPromptCard")
    }

    @ViewBuilder private var actions: some View {
        Button { copy(openChatGPT: false) } label: {
            Text(localization.string(for: .characterCopyPrompt)).actionLabel()
        }
        .accessibilityIdentifier("characterCopyPrompt")
        Button { copy(openChatGPT: true) } label: {
            Text(localization.string(for: .setupCopyAndOpen)).actionLabel()
        }
        .accessibilityIdentifier("characterCopyPromptAndOpenChatGPT")
    }

    private func copy(openChatGPT: Bool) {
        let result = SpriteSheetPrompt.copy(
            SpriteSheetPrompt.load(for: localization, resourcesAt: resourcesURL),
            to: pasteboard,
            openBrowser: openChatGPT ? openBrowser : nil
        )
        feedback = result
        announce(localization.string(for: result.messageKey))
    }
}
