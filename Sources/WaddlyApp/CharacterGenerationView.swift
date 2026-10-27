import AppKit
import SwiftUI
import WaddlyCore

enum CharacterGenerationMetrics {
    static let contentSize = NSSize(width: 820, height: 640)
    static let previewSide: CGFloat = 180
    static let descriptionHeight: CGFloat = 80
}

@MainActor
struct CharacterGenerationView: View {
    @ObservedObject var draft: CharacterGenerationDraft
    let localization: LocalizationController
    let onCopy: (Bool) -> SpriteSheetPrompt.Feedback
    @StateObject private var preview: CharacterStylePreview
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedStyle: CharacterGenerationStyle?
    private typealias FeedbackState = SwiftUI.State<SpriteSheetPrompt.Feedback?>
    @FeedbackState private var feedback = nil
    private typealias CategoryState = SwiftUI.State<PetImageCategory>
    @CategoryState private var category = .idle

    init(
        draft: CharacterGenerationDraft,
        localization: LocalizationController,
        resourcesURL: URL?,
        onCopy: @escaping (Bool) -> SpriteSheetPrompt.Feedback
    ) {
        self.draft = draft
        self.localization = localization
        self.onCopy = onCopy
        _preview = StateObject(wrappedValue: CharacterStylePreview(resourcesAt: resourcesURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.sectionGap) {
                        Text(localization.string(for: .generationTitle)).font(DesignTokens.Typography.title)
                        Text(localization.string(for: .generationChooseStyle)).font(DesignTokens.Typography.heading)
                        gallery
                        previewActions { scroll.scrollTo(draft.style) }
                        descriptionInput
                        Text(localization.string(for: .generationHandoffHelp))
                            .font(DesignTokens.Typography.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(LayoutMetrics.contentInset)
                }
                .onChange(of: focusedStyle) { oldStyle, style in
                    if let oldStyle {
                        preview.stop(oldStyle, trigger: .focus)
                    }
                    if let style {
                        scroll.scrollTo(style)
                        preview.play(style, reduceMotion: reduceMotion, trigger: .focus)
                    }
                }
            }
            Divider()
            footer
        }
        .frame(
            width: CharacterGenerationMetrics.contentSize.width,
            height: CharacterGenerationMetrics.contentSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: reduceMotion) { _, _ in preview.stop() }
        .onChange(of: draft.style) { _, _ in feedback = nil }
        .onChange(of: draft.description) { _, _ in feedback = nil }
        .onDisappear { preview.stop() }
    }

    private var gallery: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: LayoutMetrics.sectionGap) {
            ForEach(CharacterGenerationStyle.allCases) { style in
                styleCard(style)
            }
        }
        .onMoveCommand { direction in
            moveSelection(direction)
        }
    }

    private func styleCard(_ style: CharacterGenerationStyle) -> some View {
        Button {
            draft.style = style
        } label: {
            VStack(spacing: DesignTokens.Spacing.sm) {
                Group {
                    if let image = preview.frame(for: style) {
                        Image(nsImage: image).resizable().interpolation(.none)
                            .scaledToFit()
                    } else {
                        Text(localization.string(for: .generationSampleUnavailable))
                            .font(DesignTokens.Typography.caption)
                    }
                }
                .frame(width: CharacterGenerationMetrics.previewSide, height: CharacterGenerationMetrics.previewSide)
                .accessibilityHidden(true)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(localization.string(for: style.nameKey))
                        .font(DesignTokens.Typography.heading)
                    if draft.style == style {
                        Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
            .stroke(draft.style == style ? Color.accentColor : Color(nsColor: .separatorColor)))
        .focused($focusedStyle, equals: style)
        .onKeyPress(.return) {
            draft.style = style
            return .handled
        }
        .accessibilityLabel(localization.string(for: style.nameKey))
        .accessibilityValue(localization.string(
            for: draft.style == style ? .generationSelected : .generationNotSelected
        ))
        .accessibilityIdentifier("generationStyle-\(style.rawValue)")
        .onHover { hovering in
            if hovering {
                preview.play(style, reduceMotion: reduceMotion, trigger: .hover)
            } else {
                preview.stop(style, trigger: .hover)
            }
        }
        .id(style)
    }

    private func previewActions(showSelected: @escaping () -> Void) -> some View {
        HStack(spacing: LayoutMetrics.actionGap) {
            Picker(localization.string(for: .generationPreview), selection: $category) {
                ForEach(PetImageCategory.allCases, id: \.self) { category in
                    Text(localization.string(for: previewKey(category))).tag(category)
                }
            }
            .pickerStyle(.menu)
            Button(localization.string(for: .generationPlayPreview)) {
                showSelected()
                preview.play(draft.style, category: category, reduceMotion: reduceMotion)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(reduceMotion || preview.samples[draft.style] == nil)
        }
        .frame(minHeight: DesignTokens.Control.auxiliaryHeight)
        .onChange(of: category) { _, _ in preview.stop() }
    }

    private func previewKey(_ category: PetImageCategory) -> LocalizationKey {
        switch category {
        case .idle: .setupPreviewIdle
        case .typing: .setupPreviewTyping
        case .enter: .setupPreviewEnter
        case .sleep: .setupPreviewSleep
        }
    }

    private var descriptionInput: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(localization.string(for: .generationDescription)).font(DesignTokens.Typography.heading)
            Text(localization.string(for: .generationDescriptionHint))
                .font(DesignTokens.Typography.caption).foregroundStyle(.secondary)
            TextEditor(text: $draft.description)
                .font(DesignTokens.Typography.body)
                .frame(height: CharacterGenerationMetrics.descriptionHeight)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .stroke(Color(nsColor: .separatorColor)))
                .accessibilityLabel(localization.string(for: .generationDescription))
                .accessibilityIdentifier("generationDescription")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if let feedback {
                Label(localization.string(for: feedback.messageKey),
                      systemImage: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(feedback.isError ? DesignTokens.Status.critical : DesignTokens.Status.positive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: LayoutMetrics.actionGap) {
                Button { dismiss() } label: {
                    Text(localization.string(for: .generationBackToImport)).actionLabel()
                }
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button { feedback = onCopy(false) } label: {
                    Text(localization.string(for: .characterCopyPrompt)).actionLabel()
                }
                Button { feedback = onCopy(true) } label: {
                    Text(localization.string(for: .setupCopyAndOpen)).actionLabel()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal, LayoutMetrics.contentInset)
        .padding(.vertical, LayoutMetrics.footerInset)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let styles = CharacterGenerationStyle.allCases
        guard let index = styles.firstIndex(of: focusedStyle ?? draft.style) else { return }
        let delta: Int
        switch direction {
        case .left: delta = -1
        case .right: delta = 1
        case .up: delta = -2
        case .down: delta = 2
        @unknown default: return
        }
        let next = index + delta
        guard styles.indices.contains(next) else { return }
        draft.style = styles[next]
        focusedStyle = styles[next]
    }
}
