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
        case .unreadableFile: .characterErrorUnreadable
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
@MainActor
struct CharacterImportView: View {
    @ObservedObject var model: CharacterImportModel
    let editor: AnimationSettingsModel
    let localization: LocalizationController
    let titleKey: LocalizationKey
    let primaryKey: LocalizationKey
    let onPrimary: () -> Void
    let onCancel: () -> Void
    /// Opens the native picker. Returns `nil` when the user cancels.
    let pickFile: () -> URL?
    let pasteboard: NSPasteboard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 20) {
                acquisition
                CharacterPreviewHost(
                    localization: localization,
                    frames: model.stagedFrames,
                    placeholder: localization.string(for: .characterEmptyPreview)
                )
                .frame(width: 320, height: 300)
            }
            metadata
            footer
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refreshClipboardAvailability(from: pasteboard) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshClipboardAvailability(from: pasteboard)
        }
        .sheet(isPresented: $model.isEditingFrames) {
            CharacterFrameEditor(importModel: model, editor: editor, localization: localization)
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
    }

    var acquisition: some View {
        VStack(alignment: .leading, spacing: 10) {
            dropZone
            HStack(spacing: 10) {
                Button(localization.string(for: .characterChooseFile), action: chooseFile)
                    .accessibilityIdentifier("characterChooseFile")
                Button(localization.string(for: .characterPaste), action: paste)
                    .keyboardShortcut("v", modifiers: .command)
                    .help(pasteHint)
                    .accessibilityLabel("\(localization.string(for: .characterPaste)) — \(pasteHint)")
                    .accessibilityIdentifier("characterPaste")
                Text(localization.string(for: .characterPasteShortcut))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The tooltip/VoiceOver hint: what paste would do right now.
    var pasteHint: String {
        localization.string(for: model.clipboardHasImage ? .characterPasteHelp : .characterClipboardEmpty)
    }

    var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(localization.string(for: .characterDropInstruction))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(localization.string(for: .characterDropHint))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            let pngs = urls.filter { $0.pathExtension.lowercased() == "png" }
            guard !pngs.isEmpty else { return false }
            Task { await model.stageFiles(at: pngs) }
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.string(for: .characterDropInstruction))
    }

    var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let sourceDimension = model.sourceDimension, let cellSize = model.cellSize {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(localization.string(for: .characterValidStatus), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(sourceLabel(sourceDimension: sourceDimension, cellSize: cellSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(localization.string(for: .characterEditFrames)) {
                    model.isEditingFrames = true
                }
                .accessibilityIdentifier("characterEditFrames")
            } else {
                Text(localization.string(for: .characterMetadataPlaceholder))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func sourceLabel(sourceDimension: Int, cellSize: Int) -> String {
        let name = model.sourceName ?? localization.string(for: .characterClipboardSource)
        return String(
            format: localization.string(for: .characterDimensionsFormat),
            name,
            sourceDimension,
            cellSize
        )
    }

    var footer: some View {
        HStack {
            Button(localization.string(for: .characterCancel), action: onCancel)
                .accessibilityIdentifier("characterCancel")
            Spacer()
            Button(localization.string(for: primaryKey), action: onPrimary)
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

/// Hosts the existing AppKit preview pane so the shared screen uses the app's one reaction preview.
@MainActor
private struct CharacterPreviewHost: NSViewRepresentable {
    let localization: LocalizationController
    let frames: PetImageSet?
    let placeholder: String

    func makeNSView(context: Context) -> SetupPreviewPane {
        let pane = SetupPreviewPane(frame: .zero)
        pane.configure(localization: localization, showsControls: true)
        return pane
    }

    func updateNSView(_ pane: SetupPreviewPane, context: Context) {
        if let frames, frames.isComplete {
            pane.showPet(frames, caption: "", sleeping: false)
        } else {
            pane.showPlaceholder(symbol: "pawprint", message: placeholder, caption: "")
        }
    }
}
