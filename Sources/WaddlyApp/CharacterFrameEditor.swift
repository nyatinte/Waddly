import AppKit
import SwiftUI
import WaddlyCore

/// Window/sheet geometry for the frame editor. The parent screens stay at their existing sizes; this
/// editor asks for a child-sized surface when the display allows it and falls back to a still-usable
/// minimum on smaller screens.
enum FrameEditorMetrics {
    static let preferredSize = NSSize(width: 1320, height: 800)
    static let minimumSize = NSSize(width: 1040, height: 700)
    static let compactBreakpoint: CGFloat = 1160
    static let sidebarWidth: CGFloat = 306
    static let inspectorWidth: CGFloat = 300
    static let compactInspectorWidth: CGFloat = 268
    static let compactRailWidth: CGFloat = 58
    /// Header, navigation, result preview, gaps and vertical padding around the editing canvas.
    static let centerReservedHeight: CGFloat = 430
    static let minimumCanvasHeight: CGFloat = 240

    static func resolvedSize(for screen: NSScreen? = NSScreen.main) -> NSSize {
        guard let visible = screen?.visibleFrame else { return preferredSize }
        let width = min(preferredSize.width, max(minimumSize.width, visible.width - 80))
        let height = min(preferredSize.height, max(minimumSize.height, visible.height - 120))
        return NSSize(width: width, height: height)
    }
}

/// The frame-alignment editor presented from the shared character-import flow.
///
/// It is a staged child surface: Done renders the nine adjusted frames into the parent draft only.
/// The parent Apply persists, and parent Cancel discards, exactly as before.
struct CharacterFrameEditor: View {
    let localization: LocalizationController
    @StateObject private var model: CharacterFrameEditorModel
    @Environment(\.dismiss) private var dismiss
    private let explicitSize: NSSize?

    init(
        importModel: CharacterImportModel,
        localization: LocalizationController,
        size: NSSize? = nil
    ) {
        self.localization = localization
        explicitSize = size
        _model = StateObject(wrappedValue: CharacterFrameEditorModel(
            importModel: importModel,
            localization: localization
        ))
    }

    /// Snapshot/test seam: uses a model that was prepared synchronously.
    init(
        model: CharacterFrameEditorModel,
        localization: LocalizationController,
        size: NSSize? = nil
    ) {
        self.localization = localization
        explicitSize = size
        _model = StateObject(wrappedValue: model)
    }

    private var contentSize: NSSize {
        explicitSize ?? FrameEditorMetrics.resolvedSize()
    }

    var body: some View {
        FrameEditorContent(model: model, localization: localization, onDone: done)
            .frame(width: contentSize.width, height: contentSize.height)
            // Done returns edits to the parent draft; prevent an accidental sheet dismissal from
            // silently discarding work in the editor.
            .interactiveDismissDisabled()
            .task { await model.prepare() }
            .onDisappear { model.releaseResources() }
    }

    private func done() {
        guard model.needsStaging else {
            dismiss()
            return
        }
        Task {
            if await model.stageIntoDraft() {
                dismiss()
            }
        }
    }
}

@MainActor
private struct FrameEditorContent: View {
    @ObservedObject var model: CharacterFrameEditorModel
    let localization: LocalizationController
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            if model.isLoading {
                loading
            } else if model.composeFailed {
                failure
            } else {
                editorBody
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var titleBar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(localization.string(for: .frameEditorWindowTitle))
                    .font(DesignTokens.Typography.title)
                Text(localization.string(for: model.isSheetMode
                        ? .frameEditorSubtitle
                        : .frameEditorSubtitleIndividual))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignTokens.Spacing.md)
            if model.isComposing {
                ProgressView().controlSize(.small)
            }
            Button {
                model.resetAll()
            } label: {
                Text(localization.string(for: .frameEditorResetAll))
                    .actionLabel()
            }
            .controlSize(.large)
            .disabled(!model.hasEdits || model.isComposing)
            .accessibilityIdentifier("frameEditorResetAll")
            Button {
                onDone()
            } label: {
                Text(localization.string(for: .frameEditorDone))
                    .actionLabel()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isComposing)
            .accessibilityIdentifier("frameEditorDone")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private var loading: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
            Text(localization.string(for: .frameEditorLoading))
                .font(DesignTokens.Typography.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failure: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(DesignTokens.Status.warning)
            Text(localization.string(for: .frameEditorComposeFailed))
                .font(DesignTokens.Typography.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.xxl)
    }

    private var editorBody: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < FrameEditorMetrics.compactBreakpoint
            HStack(spacing: 0) {
                if compact {
                    FrameEditorCompactRail(model: model)
                        .frame(width: FrameEditorMetrics.compactRailWidth, height: geometry.size.height)
                    Divider()
                } else {
                    FrameEditorSidebar(model: model)
                        .frame(width: FrameEditorMetrics.sidebarWidth, height: geometry.size.height)
                    Divider()
                }
                FrameEditorCenterColumn(model: model, localization: localization)
                    .frame(height: geometry.size.height)
                Divider()
                FrameEditorInspector(model: model)
                    .frame(width: compact
                        ? FrameEditorMetrics.compactInspectorWidth
                        : FrameEditorMetrics.inspectorWidth, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
