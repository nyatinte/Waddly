import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import WaddlyCore

extension CharacterImportFailure {
    /// The one concrete inline message for each failure, so no case can fall through to a generic one.
    var messageKey: LocalizationKey {
        switch self {
        case let .sheet(reason): reason.messageKey
        case .noClipboardImage: .characterClipboardEmpty
        case .multipleFiles: .characterErrorMultipleFiles
        }
    }
}

extension PetSheetValidationFailure {
    var messageKey: LocalizationKey {
        switch self {
        case .notPNG: .characterErrorNotPNG
        case .unreadable: .characterErrorUnreadable
        case .fileTooLarge: .characterErrorFileTooLarge
        case .notSquare: .characterErrorNotSquare
        case .gridNotDivisible: .characterErrorGridNotDivisible
        case .dimensionTooLarge: .characterErrorDimensionTooLarge
        case .noTransparency: .characterErrorNoTransparency
        case .frameExtractionFailed: .characterErrorFrameExtraction
        }
    }
}

/// The shared acquisition, inspection, and apply surface. Only the primary action's label and the
/// surrounding navigation differ between the setup Pet step and Settings → Change Character.
///
/// The screen switches shape with the draft: before an import it spends the whole left column on
/// acquiring a sheet, and afterwards that column collapses into one file card with the two actions
/// that still make sense (replace, edit frames). Apply never moves out of the pinned footer, so the
/// same position always means the same thing.
@MainActor
struct CharacterImportView: View {
    @ObservedObject var model: CharacterImportModel
    let localization: LocalizationController
    let titleKey: LocalizationKey
    let primaryKey: LocalizationKey
    let onPrimary: () -> Void
    let onCancel: () -> Void
    let onPreviewPaneCreated: (SetupPreviewPane) -> Void
    let isPreviewActive: () -> Bool
    let onPreviewHostDisappear: () -> Void
    /// Opens the native picker. Returns `nil` when the user cancels.
    let pickFile: () -> URL?
    let pasteboard: NSPasteboard
    var showsPrompt = false
    var promptResourcesURL: URL? = Bundle.main.resourceURL

    var promptCard: CharacterPromptCard {
        CharacterPromptCard(
            localization: localization,
            pasteboard: pasteboard,
            onClipboardChange: { model.refreshClipboardAvailability(from: pasteboard) },
            resourcesURL: promptResourcesURL
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, LayoutMetrics.contentInset)
                .padding(.top, LayoutMetrics.contentInset)
                .padding(.bottom, LayoutMetrics.sectionGap)
            workingArea
                .padding(.horizontal, LayoutMetrics.contentInset)
                .padding(.bottom, LayoutMetrics.sectionGap)
                .frame(maxHeight: .infinity)
            Divider()
            footer
                .padding(.horizontal, LayoutMetrics.contentInset)
                .padding(.vertical, LayoutMetrics.footerInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refreshClipboardAvailability(from: pasteboard) }
        .onDisappear(perform: onPreviewHostDisappear)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshClipboardAvailability(from: pasteboard)
        }
        .sheet(isPresented: $model.isEditingFrames) {
            CharacterFrameEditor(importModel: model, localization: localization)
        }
    }
}

@MainActor
private extension CharacterImportView {
    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localization.string(for: titleKey))
                .font(.title3.weight(.semibold))
            Text(localization.string(for: .characterSubtitle))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Import on the left, the one reaction preview on the right. Both columns share the same top
    /// and bottom edge, so the shorter one can no longer leave a stray void above the footer.
    var workingArea: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.columnGap) {
            acquisition
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            CharacterPreviewHost(
                localization: localization,
                frames: model.stagedFrames,
                placeholder: localization.string(for: .characterEmptyPreview),
                onDrop: { urls in Task { await model.stageDroppedFiles(at: urls) } },
                isActive: isPreviewActive,
                onPaneCreated: onPreviewPaneCreated
            )
            .frame(width: LayoutMetrics.previewWidth)
            .frame(maxHeight: .infinity)
        }
    }

    var acquisition: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasStagedCandidate {
                stagedSheetCard
            } else {
                dropZone
                Text(localization.string(for: .characterMetadataPlaceholder))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.isReading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(localization.string(for: .characterReading))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if let failure = model.failure {
                statusLine(failure.messageKey, symbol: "exclamationmark.triangle.fill", positive: false)
                    .accessibilityIdentifier("characterImportError")
            }
            if model.commitFailed {
                statusLine(.characterCommitFailed, symbol: "exclamationmark.triangle.fill", positive: false)
                    .accessibilityIdentifier("characterCommitError")
            }
            if model.commitRejected {
                statusLine(.characterCommitRejected, symbol: "exclamationmark.triangle.fill", positive: false)
                    .accessibilityIdentifier("characterCommitRejected")
            }
            if showsPrompt {
                promptCard
            }
        }
    }

    /// The empty state: everything that starts an import lives inside this one zone.
    var dropZone: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: model.isDropTargeted ? "arrow.down.doc" : "photo.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(model.isDropTargeted ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            Text(localization.string(
                for: model.isDropTargeted ? .characterDropHighlight : .characterDropInstruction
            ))
            .font(.callout)
            .foregroundStyle(model.isDropTargeted ? Color.accentColor : Color.secondary)
            Text(localization.string(for: .characterDropHint))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button(action: chooseFile) {
                Text(localization.string(for: .characterChooseFile))
                    .actionLabel()
            }
            .controlSize(.large)
            .padding(.top, 6)
            .accessibilityIdentifier("characterChooseFile")
            pasteControl
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(model.isDropTargeted
                    ? Color.accentColor.opacity(0.12)
                    : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    model.isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: model.isDropTargeted ? 2 : 1.5, dash: [6, 4])
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.stageDroppedFiles(at: urls) }
            return true
        } isTargeted: { targeted in
            model.setDropTargeted(targeted)
        }
    }

    /// After an import the same area becomes one compact file card: the sheet's identity, its
    /// measurements, and only the two operations that still apply. It stays a drop target, so
    /// replacing by drag never needs the empty zone back.
    var stagedSheetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(sheetName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(sheetName)
                    HStack(spacing: 4) {
                        if model.isDropTargeted {
                            Text(localization.string(for: .characterDropHighlight))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text(localization.string(for: .characterValidStatus))
                                .foregroundStyle(.green)
                            Text(verbatim: "·").foregroundStyle(.tertiary)
                            Text(sheetSummary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: LayoutMetrics.actionGap) {
                Button(action: chooseFile) {
                    Text(localization.string(for: .characterReplace))
                        .actionLabel()
                }
                .controlSize(.large)
                .accessibilityIdentifier("characterChooseFile")
                Button {
                    model.isEditingFrames = true
                } label: {
                    Text(localization.string(for: .characterAdjustFrames))
                        .actionLabel()
                }
                .controlSize(.large)
                .disabled(!model.canAdjustFrames)
                .accessibilityIdentifier("characterAdjustFrames")
            }
            if !model.canAdjustFrames {
                Text(localization.string(for: .characterAdjustFramesUnavailable))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("characterAdjustFramesUnavailable")
            }
            // Replacing by clipboard has to survive the collapse, so the shortcut keeps working
            // after a sheet is staged and the empty zone is gone.
            pasteControl
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(model.isDropTargeted
                    ? Color.accentColor.opacity(0.12)
                    : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    model.isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: model.isDropTargeted ? 2 : 1
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.stageDroppedFiles(at: urls) }
            return true
        } isTargeted: { targeted in
            model.setDropTargeted(targeted)
        }
    }

    /// The clipboard import is the second way into the same zone, not a third button elsewhere.
    var pasteControl: some View {
        HStack(spacing: 6) {
            Button(localization.string(for: .characterPaste), action: paste)
                .buttonStyle(.link)
                .keyboardShortcut("v", modifiers: .command)
                .help(pasteHint)
                .foregroundStyle(model.clipboardHasImage ? Color.accentColor : Color.secondary)
                .opacity(model.clipboardHasImage ? 1 : 0.6)
                .accessibilityLabel("\(localization.string(for: .characterPaste)) — \(pasteHint)")
                .accessibilityIdentifier("characterPaste")
            Text(localization.string(for: .characterPasteShortcut))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// The tooltip/VoiceOver hint: what paste would do right now.
    var pasteHint: String {
        localization.string(for: model.clipboardHasImage ? .characterPasteHelp : .characterClipboardEmpty)
    }

    var sheetName: String {
        if let name = model.sourceName {
            return name
        }
        // A clipboard import has no filename but does have measurements; a saved pet has neither.
        if model.sourceDimension != nil {
            return localization.string(for: .characterClipboardSource)
        }
        return localization.string(for: .characterCurrentCharacter)
    }

    var sheetSummary: String {
        if let sourceDimension = model.sourceDimension, let cellSize = model.cellSize {
            return String(
                format: localization.string(for: .characterCellMetricsFormat),
                sourceDimension,
                cellSize
            )
        }
        let count = PetImageCategory.allCases.reduce(0) { total, category in
            total + (model.stagedFrames?[category].count ?? 0)
        }
        return String(format: localization.string(for: .characterFrameCountFormat), count)
    }

    var footer: some View {
        HStack(spacing: LayoutMetrics.actionGap) {
            Button(action: onCancel) {
                Text(localization.string(for: .characterCancel))
                    .actionLabel()
            }
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
            .disabled(model.isApplying)
            .accessibilityIdentifier("characterCancel")
            Spacer(minLength: 0)
            Button(action: onPrimary) {
                Text(localization.string(for: primaryKey))
                    .actionLabel()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canApply)
            .accessibilityIdentifier("characterPrimary")
        }
    }

    func statusLine(_ key: LocalizationKey, symbol: String, positive: Bool) -> some View {
        Label(localization.string(for: key), systemImage: symbol)
            .font(.callout)
            .foregroundStyle(positive ? Color.green : Color.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    func chooseFile() {
        guard let url = pickFile() else { return }
        Task { await model.stageFiles(at: [url]) }
    }

    func paste() {
        Task { await model.stageClipboard(from: pasteboard) }
    }
}
