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
    /// The window is not resizable: the shared screen is pinned to this content size so the SwiftUI
    /// layout and the window agree, exactly like the fixed-size setup wizard.
    static let contentSize = NSSize(width: 880, height: 580)
    private let localization: LocalizationController
    private let presenter: WindowPresenter
    private let onClose: @MainActor () -> Void
    private var isConfirmingClose = false

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
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = localization.string(for: .characterWindowTitle)
        window.contentMinSize = Self.contentSize
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Brings the window forward. A fresh open reloads the committed pet; an already visible window
    /// is only focused, so re-invoking the menu item never discards a staged draft.
    func focus() {
        presenter.activate()
        guard let window else { return }
        if Self.shouldReloadDraft(isVisible: window.isVisible, isMiniaturized: window.isMiniaturized) {
            model.reload()
        }
        presenter.focus(window)
    }

    static func shouldReloadDraft(isVisible: Bool, isMiniaturized: Bool) -> Bool {
        !isVisible && !isMiniaturized
    }

    func refreshLocalization() {
        window?.title = localization.string(for: .characterWindowTitle)
        frameEditorModel.refreshLocalization()
        model.refreshLocalization()
    }

    /// Closing with staged changes asks first; an untouched or freshly applied window closes at once.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !model.isApplying else { return false }
        guard model.isDirty, !isConfirmingClose else { return true }
        confirmDiscard { [weak self] in
            guard let self else { return }
            isConfirmingClose = true
            close()
        }
        return false
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
            onPrimary: { [weak self] in _ = self?.applyAndClose() },
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
            host.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            // The window is not resizable; pin the hosting view to the design size so its content
            // height cannot pull the window taller than the layout it was designed for.
            host.widthAnchor.constraint(equalToConstant: Self.contentSize.width),
            host.heightAnchor.constraint(equalToConstant: Self.contentSize.height)
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

    @discardableResult
    func applyAndClose() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            guard await model.apply() else { return }
            close()
        }
    }

    private func cancel() {
        guard !model.isApplying else { return }
        guard model.isDirty else {
            close()
            return
        }
        confirmDiscard { [weak self] in self?.close() }
    }

    private func confirmDiscard(then discard: @escaping @MainActor () -> Void) {
        guard !model.isApplying else { return }
        guard let window else {
            discard()
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
            self?.finishDiscard(discard)
        }
    }

    private func finishDiscard(_ discard: @MainActor () -> Void) {
        guard !model.isApplying else { return }
        discard()
    }
}
