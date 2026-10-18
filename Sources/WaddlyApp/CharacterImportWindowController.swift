import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WaddlyCore

/// Post-setup character management: the shared import screen in its own window.
///
/// Import is not apply. The staged draft lives in the window until Apply succeeds; Cancel or close
/// asks before discarding, and only when something was actually staged.
@MainActor
final class CharacterImportWindowController: NSWindowController, NSWindowDelegate {
    let model: CharacterImportModel
    let frameEditorModel: AnimationSettingsModel
    private let localization: LocalizationController
    private let presenter: WindowPresenter
    private let onClose: @MainActor () -> Void

    init(
        model: CharacterImportModel,
        localization: LocalizationController,
        presenter: WindowPresenter,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.model = model
        frameEditorModel = CharacterFrameEditor.makeModel(importModel: model, localization: localization)
        self.localization = localization
        self.presenter = presenter
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 880, height: 580)),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = localization.string(for: .characterWindowTitle)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Opens the window on the pet that is actually committed now, so nothing stale is shown.
    func focus() {
        model.reload()
        presenter.activate()
        guard let window else { return }
        presenter.focus(window)
    }

    func refreshLocalization() {
        window?.title = localization.string(for: .characterWindowTitle)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window?.delegate = nil
        onClose()
    }

    private func buildContent() {
        let root = PetImageDropView()
        root.idleBorderWidth = 0
        root.onDrop = { [weak self] urls in
            Task { await self?.model.stageFiles(at: urls) }
        }
        let host = NSHostingView(rootView: CharacterImportView(
            model: model,
            editor: frameEditorModel,
            localization: localization,
            titleKey: .characterChangeTitle,
            primaryKey: .characterApply,
            onPrimary: { [weak self] in self?.applyAndClose() },
            onCancel: { [weak self] in self?.cancel() },
            pickFile: { [weak self] in self?.pickFile() },
            pasteboard: .general
        ))
        host.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            host.topAnchor.constraint(equalTo: root.topAnchor),
            host.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        window?.contentView = root
    }

    private func pickFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = localization.string(for: .characterChooseFile)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func applyAndClose() {
        Task { [weak self] in
            guard let self else { return }
            await model.apply()
            guard !model.commitFailed else { return }
            close()
        }
    }

    private func cancel() {
        guard model.isDirty else {
            close()
            return
        }
        guard let window else {
            close()
            return
        }
        let alert = NSAlert()
        alert.messageText = localization.string(for: .characterDiscardTitle)
        alert.informativeText = localization.string(for: .characterDiscardMessage)
        alert.alertStyle = .warning
        alert.addButton(withTitle: localization.string(for: .characterDiscardConfirm))
        alert.addButton(withTitle: localization.string(for: .characterCancel))
        presenter.presentAlert(alert, window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.close()
        }
    }
}
