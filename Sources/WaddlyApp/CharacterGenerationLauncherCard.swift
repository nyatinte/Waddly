import AppKit
import SwiftUI

/// Points at the dedicated generation screen from Change Character. The screen owns the style,
/// the description, and the prompt copy, so this card only explains the hand-off and opens it.
@MainActor
struct CharacterGenerationLauncherCard: View {
    let localization: LocalizationController
    var onOpen: @MainActor () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(localization.string(for: .characterPromptTitle))
                .font(DesignTokens.Typography.heading)
            Text(localization.string(for: .characterPromptBody))
                .font(DesignTokens.Typography.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onOpen) {
                Label(
                    localization.string(for: .characterGenerationLauncherButton),
                    systemImage: "sparkles"
                )
                .actionLabel()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("openCharacterGeneration")
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(Color(nsColor: .separatorColor))
        )
        .accessibilityIdentifier("characterGenerationLauncher")
    }
}
