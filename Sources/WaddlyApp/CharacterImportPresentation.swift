import SwiftUI

/// The card that replaces the drop zone once the screen has a complete frame set: either the pet
/// saved right now, or a draft that would replace it. A draft never reads as the current pet, and a
/// failed or rejected save stays pending instead of claiming success.
enum CharacterDraftStatus: Equatable {
    case currentInUse
    case notSaved

    var messageKey: LocalizationKey {
        switch self {
        case .currentInUse: .characterStatusCurrentInUse
        case .notSaved: .characterStatusNotSaved
        }
    }

    var symbol: String {
        switch self {
        case .currentInUse: "checkmark.circle.fill"
        case .notSaved: "circle"
        }
    }

    /// Only the persisted pet is a positive status; a draft stays pending (secondary) until Apply.
    var color: Color {
        switch self {
        case .currentInUse: DesignTokens.Status.positive
        case .notSaved: .secondary
        }
    }
}

@MainActor
extension CharacterImportView {
    /// What the replaced drop zone's card states: the saved pet, or a draft that is not saved yet.
    var draftStatus: CharacterDraftStatus {
        model.hasUnsavedChanges ? .notSaved : .currentInUse
    }

    /// Whether the footer's one action can run in this host: setup's Continue may commit an unchanged,
    /// already valid pet, while Change Character's Apply needs a difference to save.
    var isPrimaryActionEnabled: Bool {
        model.canPerformPrimaryAction(requiresChange: primaryRequiresChange)
    }

    /// Setup hands the user to ChatGPT before the image exists, so the empty drop zone it jumped to
    /// has to say why it is already on screen.
    var handoffNote: some View {
        Label(localization.string(for: .characterPromptHandoff), systemImage: "sparkles")
            .font(DesignTokens.Typography.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("characterPromptHandoff")
    }
}
