import AppKit
import WaddlyCore

private struct PetShareAssets: Sendable {
    let directory: URL
    let spriteURL: URL
    let movieURL: URL

    static func make(from images: PetImageSet) throws -> PetShareAssets {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaddlyShare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let spriteURL = directory.appendingPathComponent("pet-sprite.png")
        let movieURL = directory.appendingPathComponent("pet-animation.mp4")
        do {
            guard let png = PetShareExporter.spriteSheetPNG(from: images) else {
                throw PetShareExportError.incompleteImageSet
            }
            try png.write(to: spriteURL, options: .atomic)
            try PetShareExporter.writeMovie(from: images, to: movieURL)
            return PetShareAssets(directory: directory, spriteURL: spriteURL, movieURL: movieURL)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

@MainActor
final class PetShareWindowController: NSWindowController, NSWindowDelegate {
    private let images: PetImageSet
    private let localization: LocalizationController
    private let shareView: PetShareDialogView
    private var generationTask: Task<Void, Never>?
    private var assets: PetShareAssets?
    private var isClosed = false
    var onClose: (() -> Void)?

    init(images: PetImageSet, localization: LocalizationController) {
        self.images = images
        self.localization = localization
        shareView = PetShareDialogView(localization: localization)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 410),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = localization.string(for: .shareTitle)
        window.contentView = shareView
        window.center()
        super.init(window: window)
        window.delegate = self
        shareView.onCopySprite = { [weak self] in self?.copySprite() }
        shareView.onCopyMovie = { [weak self] in self?.copyMovie() }
        shareView.onOpenX = { [weak self] in self?.openX() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshLocalization() {
        window?.title = localization.string(for: .shareTitle)
        shareView.refreshLocalization()
    }

    func prepareAssets() {
        guard generationTask == nil else { return }
        generationTask = Task { [weak self, images] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try PetShareAssets.make(from: images) }
            }.value
            guard let self else {
                if case let .success(assets) = result {
                    try? FileManager.default.removeItem(at: assets.directory)
                }
                return
            }
            if isClosed {
                if case let .success(assets) = result {
                    try? FileManager.default.removeItem(at: assets.directory)
                }
                return
            }
            switch result {
            case let .success(assets):
                self.assets = assets
                shareView.showAssets(
                    spriteURL: assets.spriteURL,
                    movieURL: assets.movieURL,
                    moviePoster: images[.idle].first
                )
            case .failure:
                shareView.showError()
            }
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // The context menu is still tracking during its action; activate after it closes.
        Task { @MainActor [weak self] in
            guard let window = self?.window, window.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        isClosed = true
        generationTask?.cancel()
        shareView.stopPlayback()
        if let assets {
            try? FileManager.default.removeItem(at: assets.directory)
        }
        onClose?()
    }

    private func copySprite() {
        guard let assets, let data = try? Data(contentsOf: assets.spriteURL, options: .mappedIfSafe) else { return }
        if PetShareClipboard.copyPNG(data) {
            shareView.didCopySprite()
        } else {
            NSSound.beep()
        }
    }

    private func copyMovie() {
        guard let assets, let data = try? Data(contentsOf: assets.movieURL, options: .mappedIfSafe) else { return }
        if PetShareClipboard.copyMovie(data) {
            shareView.didCopyMovie()
        } else {
            NSSound.beep()
        }
    }

    private func openX() {
        if let url = Self.xPostURL(text: localization.string(for: .shareXDraft)) {
            NSWorkspace.shared.open(url)
        }
    }

    static func xPostURL(text: String) -> URL? {
        var components = URLComponents(string: "https://twitter.com/intent/tweet")
        components?.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "hashtags", value: "ShareMyWaddly")
        ]
        return components?.url
    }
}
