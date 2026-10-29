import AppKit
import SwiftUI

/// The large sample frame and the nine-frame strip. Both read the same loaded sample, so the strip
/// can never point at a frame the large view does not have.
@MainActor
struct CharacterStylePreview: View {
    @ObservedObject var model: CharacterGenerationModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(model.localization.string(for: .characterGenerationPreviewTitle))
                    .font(DesignTokens.Typography.title)
                Spacer(minLength: 0)
                Text(model.localization.string(for: .characterGenerationFrames))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Text(model.localization.string(for: .characterGenerationPreviewCaption))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            largeFrame
            frameStrip
        }
    }

    private var largeFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(Color(nsColor: .controlBackgroundColor))
            if let image = model.previewFrame {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(DesignTokens.Spacing.lg)
                    .accessibilityHidden(true)
            } else {
                Text(model.localization.string(for: .characterGenerationSampleUnavailable))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: CharacterGenerationMetrics.previewHeight)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(Color(nsColor: .separatorColor))
        )
        .onHover { hovering in
            if hovering {
                model.play(.preview, reduceMotion: reduceMotion)
            } else {
                model.stopPlayback(.preview)
            }
        }
        .accessibilityIdentifier("generationPreview")
    }

    private var frameStrip: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(0 ..< 9, id: \.self) { index in
                frameButton(index)
            }
        }
    }

    private func frameButton(_ index: Int) -> some View {
        let frames = model.currentFrames
        let hasFrame = frames.indices.contains(index)
        let isSelected = hasFrame && index == model.previewIndex
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
        return Button { model.previewIndex = index } label: {
            ZStack {
                shape.fill(Color(nsColor: .textBackgroundColor))
                if hasFrame {
                    Image(nsImage: frames[index])
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(
                            width: CharacterGenerationMetrics.frameStripSide,
                            height: CharacterGenerationMetrics.frameStripSide
                        )
                        .clipped()
                }
            }
            .frame(
                width: CharacterGenerationMetrics.frameStripSide,
                height: CharacterGenerationMetrics.frameStripSide
            )
            .clipShape(shape)
            .overlay(shape.stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor)))
        }
        .buttonStyle(.plain)
        .disabled(!hasFrame)
        .accessibilityLabel(Text(String(
            format: model.localization.string(for: .characterGenerationFrameLabelFormat),
            index + 1
        )))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("generationFrame-\(index)")
    }
}

/// The copy hand-off. The prompt is shown verbatim because that is exactly what lands on the
/// clipboard; opening ChatGPT is a separate, explicit action.
@MainActor
struct GenerationPromptCard: View {
    @ObservedObject var model: CharacterGenerationModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(model.localization.string(for: .characterGenerationPromptTitle))
                .font(DesignTokens.Typography.title)
            Text(model.localization.string(for: .characterGenerationPromptBody))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            promptText
            actions
            if let feedback = model.feedback {
                Label(
                    model.localization.string(for: feedback.messageKey),
                    systemImage: feedback.isError
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill"
                )
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(feedback.isError ? DesignTokens.Status.critical : DesignTokens.Status.positive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("generationPromptFeedback")
            }
            Text(model.localization.string(for: .characterGenerationFooter))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
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

    private var promptText: some View {
        ScrollView {
            Text(model.prompt)
                .font(DesignTokens.Typography.mono)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: CharacterGenerationMetrics.promptHeight)
        .padding(DesignTokens.Spacing.sm)
        .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                .stroke(Color(nsColor: .separatorColor))
        )
        .accessibilityIdentifier("generationPromptText")
    }

    private var actions: some View {
        HStack(spacing: LayoutMetrics.actionGap) {
            Button { model.copyPrompt() } label: {
                Text(model.localization.string(for: .characterGenerationCopyPrompt))
                    .actionLabel()
            }
            .accessibilityIdentifier("generationCopyPrompt")
            Button { model.copyAndOpenChatGPT() } label: {
                Text(model.localization.string(for: .characterGenerationOpenInChatGPT))
                    .actionLabel()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("generationOpenInChatGPT")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
