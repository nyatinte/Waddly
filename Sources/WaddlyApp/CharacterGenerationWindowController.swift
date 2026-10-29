import AppKit
import SwiftUI

/// Hosts the generation screen in its own window, so setup and Change Character share one surface
/// without either wizard growing a second layout mode.
@MainActor
final class CharacterGenerationWindowController: NSWindowController, NSWindowDelegate {
    let model: CharacterGenerationModel
    private let presenter: WindowPresenter
    private let onClose: @MainActor () -> Void

    init(
        model: CharacterGenerationModel,
        presenter: WindowPresenter = .live,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.model = model
        self.presenter = presenter
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CharacterGenerationMetrics.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = model.localization.string(for: .characterGenerationTitle)
        window.contentMinSize = CharacterGenerationMetrics.contentSize
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func focus() {
        presenter.activate()
        guard let window else { return }
        presenter.focus(window)
    }

    func refreshLocalization() {
        window?.title = model.localization.string(for: .characterGenerationTitle)
        model.refreshLocalization()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window?.delegate = nil
        onClose()
    }

    private func buildContent() {
        guard let window else { return }
        let host = NSHostingView(rootView: CharacterGenerationView(
            model: model,
            onClose: { [weak self] in self?.close() }
        ))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.frame = window.contentView?.bounds ?? NSRect(origin: .zero, size: CharacterGenerationMetrics.contentSize)
        window.contentView = host
    }
}
