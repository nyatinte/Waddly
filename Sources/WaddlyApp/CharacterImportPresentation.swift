import SwiftUI

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

    var color: Color {
        switch self {
        case .currentInUse: DesignTokens.Status.positive
        case .notSaved: .secondary
        }
    }
}

@MainActor
extension CharacterImportView {
    var previewStageLabel: String? {
        if isReplacing {
            return localization.string(for: .characterPreviewBeforeReplacement)
        }
        if model.isSampleCandidate {
            return localization.string(for: .characterPreviewSampleSelected)
        }
        if !model.hasStagedCandidate, sampleImages != nil {
            return localization.string(for: .characterPreviewSampleUnselected)
        }
        return nil
    }

    var footer: some View {
        HStack(spacing: LayoutMetrics.actionGap) {
            if let onCancel {
                Button(action: onCancel) {
                    Text(localization.string(for: .characterCancel))
                        .actionLabel()
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .disabled(model.isApplying)
                .accessibilityIdentifier("characterCancel")
            } else if let sampleImages, !model.hasStagedCandidate {
                Button {
                    model.stageSample(sampleImages, name: localization.string(for: .setupDemoLabel))
                } label: {
                    Text(localization.string(for: .setupTrySample)).actionLabel()
                }
                .controlSize(.large)
                .disabled(model.isReading || model.isApplying)
                .accessibilityIdentifier("trySamplePet")
            }
            Spacer(minLength: 0)
            Button(action: onPrimary) {
                Text(localization.string(for: primaryKey))
                    .actionLabel()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!isPrimaryActionEnabled || isReplacing)
            .accessibilityIdentifier("characterPrimary")
        }
    }

    var draftStatus: CharacterDraftStatus {
        model.hasUnsavedChanges ? .notSaved : .currentInUse
    }

    var isPrimaryActionEnabled: Bool {
        model.canApply && (!primaryRequiresChange || model.hasUnsavedChanges)
    }
}
