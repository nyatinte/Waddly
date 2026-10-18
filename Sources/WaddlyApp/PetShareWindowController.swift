import AppKit
import WaddlyCore

struct PetShareAssets: Sendable {
    let spriteURL: URL
    let movieURL: URL

    static func make(
        from images: PetImageSet,
        cancellation: PetShareExportCancellation,
        writeMovie: PetShareWindowController.MovieWriter
    ) throws -> PetShareAssets {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaddlyShare-\(UUID().uuidString)")
        let spriteURL = base.appendingPathExtension("png")
        let movieURL = base.appendingPathExtension("mp4")
        do {
            guard let png = PetShareExporter.spriteSheetPNG(from: images) else {
                throw PetShareExportError.incompleteImageSet
            }
            try png.write(to: spriteURL, options: .atomic)
            try writeMovie(images, movieURL, cancellation)
            return PetShareAssets(spriteURL: spriteURL, movieURL: movieURL)
        } catch {
            // The movie is the export's output: it deletes it on the queue that owns the writer, which may
            // still be running when a stalled export gives up waiting. Removing a directory here would
            // pull the output out from under an active `AVAssetWriter`, so this path only discards the
            // sprite it wrote itself.
            try? FileManager.default.removeItem(at: spriteURL)
            throw error
        }
    }

    /// Removes both assets. Only call this once the export has finished with the movie.
    func remove() {
        try? FileManager.default.removeItem(at: spriteURL)
        try? FileManager.default.removeItem(at: movieURL)
    }
}

@MainActor
final class PetShareWindowController: NSWindowController, NSWindowDelegate {
    /// Writes the dialog's movie. Tests inject a writer that reports when closing cancels generation.
    typealias MovieWriter = @Sendable (PetImageSet, URL, PetShareExportCancellation) throws -> Void

    private let images: PetImageSet
    private let localization: LocalizationController
    private let presenter: WindowPresenter
    private let shareView: PetShareDialogView
    private let writeMovie: MovieWriter
    private let cancellation = PetShareExportCancellation()
    private var generationTask: Task<Void, Never>?
    private var assets: PetShareAssets?
    private var isClosed = false
    var onClose: (() -> Void)?

    init(
        images: PetImageSet,
        localization: LocalizationController,
        presenter: WindowPresenter = .live,
        writeMovie: @escaping MovieWriter = { images, url, cancellation in
            try PetShareExporter.writeMovie(from: images, to: url, cancellation: cancellation)
        }
    ) {
        self.images = images
        self.localization = localization
        self.presenter = presenter
        self.writeMovie = writeMovie
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
        let exportCancellation = cancellation
        let movieWriter = writeMovie
        generationTask = Task { [weak self, images] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try PetShareAssets.make(
                        from: images,
                        cancellation: exportCancellation,
                        writeMovie: movieWriter
                    )
                }
            }.value
            guard let self else {
                if case let .success(assets) = result {
                    assets.remove()
                }
                return
            }
            if isClosed {
                if case let .success(assets) = result {
                    assets.remove()
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
        guard let window else { return }
        presenter.reveal(window)
        // The context menu is still tracking during its action; activate after it closes.
        Task { @MainActor [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            presenter.activate()
            presenter.focus(window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        isClosed = true
        // Stop the encoder itself, not just the task that awaits it. The export queue retains ownership
        // of a pending movie; the controller removes both assets only after a successful export.
        cancellation.cancel()
        generationTask?.cancel()
        shareView.stopPlayback()
        if let assets {
            assets.remove()
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
