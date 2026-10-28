import AppKit
import SwiftUI

/// Component geometry for the generation screen. Only sizes that are specific to this surface live
/// here; spacing, type, radius, and color still come from the shared tokens.
enum CharacterGenerationMetrics {
    static let contentSize = NSSize(width: 1040, height: 720)
    static let previewHeight: CGFloat = 196
    static let promptHeight: CGFloat = 118
    static let descriptionHeight: CGFloat = 72
    static let styleThumbnailHeight: CGFloat = 92
    static let frameStripSide: CGFloat = 34
}

/// The six styles as comparable samples. Cards are the only place a style is chosen, so the
/// selection state, the sample art, and the label always change together.
@MainActor
struct CharacterStyleGallery: View {
    @ObservedObject var model: CharacterGenerationModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(model.localization.string(for: .characterGenerationStyleTitle))
                .font(DesignTokens.Typography.title)
            Text(model.localization.string(for: .characterGenerationStyleCaption))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(
                repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.md), count: 3
            ), spacing: DesignTokens.Spacing.md) {
                ForEach(CharacterStyle.allCases) { style in
                    card(style)
                }
            }
        }
    }

    private func card(_ style: CharacterStyle) -> some View {
        CharacterStyleCard(
            name: model.localization.string(for: style.nameKey),
            sample: model.sampleFrames[style]?.first,
            unavailableText: model.localization.string(for: .characterGenerationSampleUnavailable),
            isSelected: model.style == style,
            identifier: "generationStyle-\(style.rawValue)",
            onSelect: { model.style = style }
        )
    }
}

/// One comparable style sample. Split out of the grid so the card's modifier chain stays small
/// enough for the type checker.
@MainActor
private struct CharacterStyleCard: View {
    let name: String
    let sample: NSImage?
    let unavailableText: String
    let isSelected: Bool
    let identifier: String
    let onSelect: @MainActor () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: DesignTokens.Spacing.xs) {
                thumbnail
                    .frame(maxWidth: .infinity)
                    .frame(height: CharacterGenerationMetrics.styleThumbnailHeight)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                    )
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(DesignTokens.Typography.title)
                                .foregroundStyle(Color.accentColor)
                                .padding(DesignTokens.Spacing.xs)
                                .accessibilityHidden(true)
                        }
                    }
                Text(name)
                    .font(DesignTokens.Typography.caption)
                    .lineLimit(1)
            }
            .padding(DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: shape)
        .overlay(shape.stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor)))
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
    }

    @ViewBuilder private var thumbnail: some View {
        if let sample {
            Image(nsImage: sample)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        } else {
            Text(unavailableText)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(DesignTokens.Spacing.sm)
        }
    }
}

/// How to brief the external generator. The selection changes the guidance, never the prompt's
/// structural contract, so every mode stays compatible with the same nine cells.
@MainActor
struct CharacterGenerationInputPicker: View {
    @ObservedObject var model: CharacterGenerationModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(model.localization.string(for: .characterGenerationFromTitle))
                .font(DesignTokens.Typography.title)
            HStack(spacing: DesignTokens.Spacing.md) {
                ForEach(CharacterGenerationInput.allCases) { input in
                    card(input)
                }
            }
        }
    }

    private func card(_ input: CharacterGenerationInput) -> some View {
        let isSelected = model.input == input
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        return Button { model.input = input } label: {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: input.symbol)
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(DesignTokens.Typography.callout)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                }
                Text(model.localization.string(for: input.titleKey))
                    .font(DesignTokens.Typography.heading)
                Text(model.localization.string(for: input.detailKey))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: shape)
        .overlay(shape.stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor)))
        .accessibilityLabel(Text(model.localization.string(for: input.titleKey)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("generationInput-\(input.rawValue)")
    }
}

/// The character line that the shared contract already asks for. The placeholder is a hint, not a
/// value: an empty field keeps the contract's own default line.
@MainActor
struct CharacterDescriptionEditor: View {
    @ObservedObject var model: CharacterGenerationModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(model.localization.string(for: .characterGenerationDescribeTitle))
                .font(DesignTokens.Typography.title)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.character)
                    .font(DesignTokens.Typography.body)
                    .scrollContentBackground(.hidden)
                    .padding(DesignTokens.Spacing.sm)
                    .frame(height: CharacterGenerationMetrics.descriptionHeight)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                            .stroke(Color(nsColor: .separatorColor))
                    )
                    .accessibilityLabel(
                        Text(model.localization.string(for: .characterGenerationDescribeTitle))
                    )
                    .accessibilityIdentifier("generationCharacter")
                if model.character.isEmpty {
                    Text(model.localization.string(for: .characterGenerationDescribePlaceholder))
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(.tertiary)
                        .padding(DesignTokens.Spacing.md)
                        .allowsHitTesting(false)
                }
            }
            Text(String(
                format: model.localization.string(for: .characterGenerationCountFormat),
                model.characterCount,
                CharacterGenerationModel.characterLimit
            ))
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("generationCharacterCount")
        }
    }
}
