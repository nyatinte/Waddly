import AppKit
import SwiftUI

/// The dedicated generation screen: choose a style, say how to brief the generator, describe the
/// character, and copy the composed prompt. Nothing on this screen stages or applies a pet.
@MainActor
struct CharacterGenerationView: View {
    @ObservedObject var model: CharacterGenerationModel
    let onClose: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: LayoutMetrics.columnGap) {
                ScrollView {
                    leftColumn
                }
                .frame(maxWidth: .infinity)
                rightColumn
                    .frame(width: LayoutMetrics.previewWidth)
            }
            .padding(.horizontal, LayoutMetrics.contentInset)
            .padding(.vertical, LayoutMetrics.sectionGap)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(
            minWidth: CharacterGenerationMetrics.contentSize.width,
            minHeight: CharacterGenerationMetrics.contentSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .task { model.loadSamplesIfNeeded() }
        .accessibilityIdentifier("characterGenerationView")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            circularButton(
                symbol: "chevron.left",
                label: model.localization.string(for: .characterGenerationBack),
                identifier: "generationBack",
                action: onClose
            )
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(model.localization.string(for: .characterGenerationTitle))
                    .font(DesignTokens.Typography.display)
                Text(model.localization.string(for: .characterGenerationSubtitle))
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            circularButton(
                symbol: "xmark",
                label: model.localization.string(for: .characterGenerationClose),
                identifier: "generationClose",
                action: onClose
            )
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, LayoutMetrics.contentInset)
        .padding(.top, DesignTokens.Spacing.xl)
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionGap) {
            CharacterStyleGallery(model: model)
            CharacterGenerationInputPicker(model: model)
            CharacterDescriptionEditor(model: model)
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionGap) {
            CharacterStylePreview(model: model)
            GenerationPromptCard(model: model)
        }
    }

    private func circularButton(
        symbol: String,
        label: String,
        identifier: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(DesignTokens.Typography.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(
                    width: DesignTokens.Control.auxiliaryHeight,
                    height: DesignTokens.Control.auxiliaryHeight
                )
                .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                .overlay(Circle().stroke(Color(nsColor: .separatorColor)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }
}
