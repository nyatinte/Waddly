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
    /// The screen's design size. Both body columns share one height, and only the footer owns the
    /// primary action, so the layout stays coherent when the window is resized above this minimum.
    static let contentSize = NSSize(width: 1040, height: 640)
    private let localization: LocalizationController
    private let presenter: WindowPresenter
    private let onClose: @MainActor () -> Void
    private var isConfirmingClose = false
    private weak var embeddedPreviewPane: SetupPreviewPane?

    init(
        model: CharacterImportModel,
        localization: LocalizationController,
        presenter: WindowPresenter,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.model = model
        self.localization = localization
        self.presenter = presenter
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
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
        model.refreshLocalization()
    }

    /// Closing with staged changes asks first; an untouched or freshly applied window closes at once.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !model.isApplying, !isConfirmingClose else { return false }
        guard model.isDirty else { return true }
        confirmDiscard { [weak self] in self?.close() }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        stopEmbeddedPreview()
        window?.contentView = nil
        window?.delegate = nil
        onClose()
    }

    private func buildContent() {
        let root = PetImageDropView()
        root.idleBorderWidth = 0
        root.shouldPreserveUnsupportedDropURLs = { true }
        root.onDrop = { [weak self] urls in
            Task { await self?.model.stageFiles(at: urls) }
        }
        let host = NSHostingView(rootView: CharacterImportView(
            model: model,
            localization: localization,
            titleKey: .characterChangeTitle,
            primaryKey: .characterApply,
            onPrimary: { [weak self] in _ = self?.applyAndClose() },
            onCancel: { [weak self] in self?.cancel() },
            onPreviewPaneCreated: { [weak self] pane in self?.embeddedPreviewPane = pane },
            isPreviewActive: { true },
            onPreviewHostDisappear: { [weak self] in self?.stopEmbeddedPreview() },
            pickFile: { [weak self] in self?.pickFile() },
            pasteboard: .general,
            showsPrompt: true
        ))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.frame = root.bounds
        root.addSubview(host)
        // The window owns the size; the hosting view follows its bounds. Referencing the host from
        // Auto Layout instead lets its ideal (flexible) height resize the window away from the
        // designed 1040 × 640 frame.
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

    private func stopEmbeddedPreview() {
        embeddedPreviewPane?.stopPlayback()
        embeddedPreviewPane = nil
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
        guard !model.isApplying, !isConfirmingClose else { return }
        guard let window else {
            discard()
            return
        }
        isConfirmingClose = true
        let alert = NSAlert()
        alert.messageText = localization.string(for: .characterDiscardTitle)
        alert.informativeText = localization.string(for: .characterDiscardMessage)
        alert.alertStyle = .warning
        alert.addButton(withTitle: localization.string(for: .characterDiscardConfirm))
        alert.addButton(withTitle: localization.string(for: .characterCancel))
        presenter.presentAlert(alert, window) { [weak self] response in
            guard let self else { return }
            isConfirmingClose = false
            guard response == .alertFirstButtonReturn else { return }
            finishDiscard(discard)
        }
    }

    private func finishDiscard(_ discard: @MainActor () -> Void) {
        guard !model.isApplying else { return }
        discard()
    }
}
