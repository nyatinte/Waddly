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

/// The system effects the dialog performs. Tests replace them to drive outcomes the system would refuse.
struct PetShareEffects: Sendable {
    /// Writes the dialog's movie. Tests inject a writer that reports when closing cancels generation.
    var writeMovie: PetShareWindowController.MovieWriter = { images, url, cancellation in
        try PetShareExporter.writeMovie(from: images, to: url, cancellation: cancellation)
    }

    var copyImage: @MainActor @Sendable (Data) -> Bool = { PetShareClipboard.copyPNG($0) }
    var publishMovie: @MainActor @Sendable (Data, String) -> URL? = { data, name in
        PetShareClipboard.publishForPasteboard(data, named: name)
    }

    var copyMovie: @MainActor @Sendable (Data, URL) -> Bool = { data, url in
        PetShareClipboard.copyMovie(data, fileURL: url)
    }

    var openURL: @MainActor @Sendable (URL) -> Bool = { NSWorkspace.shared.open($0) }
}

@MainActor
final class PetShareWindowController: NSWindowController, NSWindowDelegate {
    /// Writes the dialog's movie. Tests inject a writer that reports when closing cancels generation.
    typealias MovieWriter = @Sendable (PetImageSet, URL, PetShareExportCancellation) throws -> Void

    /// What the dialog can do right now. The view renders exactly one of these.
    enum Status: Equatable {
        case idle
        case working
        case ready
        case cancelled
        case failed
    }

    private let images: PetImageSet
    private let localization: LocalizationController
    private let presenter: WindowPresenter
    private let shareView: PetShareDialogView
    private let effects: PetShareEffects
    private let cancellation = PetShareExportCancellation()
    private var generationTask: Task<Void, Never>?
    private var assets: PetShareAssets?
    private var copyOutcome: [PetShareAssetKind: Bool] = [:]
    private var composerOpenFailed = false
    private(set) var status: Status = .idle
    var onClose: (() -> Void)?

    init(
        images: PetImageSet,
        localization: LocalizationController,
        presenter: WindowPresenter = .live,
        effects: PetShareEffects = PetShareEffects()
    ) {
        self.images = images
        self.localization = localization
        self.presenter = presenter
        self.effects = effects
        shareView = PetShareDialogView(localization: localization)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = localization.string(for: .shareTitle)
        window.contentView = shareView
        window.center()
        super.init(window: window)
        window.delegate = self
        shareView.onCopySprite = { [weak self] in self?.copy(.image) }
        shareView.onCopyMovie = { [weak self] in self?.copy(.video) }
        shareView.onOpenX = { [weak self] in self?.openX() }
        shareView.onRetry = { [weak self] in self?.prepareAssets() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshLocalization() {
        window?.title = localization.string(for: .shareTitle)
        shareView.refreshLocalization()
        for (asset, copied) in copyOutcome {
            shareView.showCopyResult(copyText(for: asset, copied: copied), failed: !copied, for: asset)
        }
        shareView.showXOpenFailure(composerOpenFailed ? localization.string(for: .shareOpenXFailed) : nil)
    }

    /// Generates the assets once. A second call while one exists or is running is ignored; a failed
    /// generation can be started again.
    func prepareAssets() {
        guard generationTask == nil, status == .idle || status == .failed else { return }
        status = .working
        copyOutcome.removeAll()
        composerOpenFailed = false
        shareView.showWorking()
        let exportCancellation = cancellation
        let effects = effects
        generationTask = Task { [weak self, images] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try PetShareAssets.make(
                        from: images,
                        cancellation: exportCancellation,
                        writeMovie: effects.writeMovie
                    )
                }
            }.value
            guard let self else {
                if case let .success(assets) = result {
                    assets.remove()
                }
                return
            }
            finishGeneration(result)
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
        status = .cancelled
        // Stop the encoder itself, not just the task that awaits it: the export polls this token, stops
        // the writer on its own queue, and deletes the movie it was writing.
        cancellation.cancel()
        generationTask = nil
        shareView.stopPlayback()
        if let assets {
            assets.remove()
        }
        assets = nil
        onClose?()
    }

    private func finishGeneration(_ result: Result<PetShareAssets, Error>) {
        generationTask = nil
        // Closing the window drops the result; its files must not outlive the dialog.
        guard status != .cancelled else {
            if case let .success(assets) = result {
                assets.remove()
            }
            return
        }
        switch result {
        case let .success(assets):
            self.assets = assets
            status = .ready
            shareView.showAssets(
                spriteURL: assets.spriteURL,
                movieURL: assets.movieURL,
                moviePoster: images[.idle].first
            )
        case .failure:
            status = .failed
            shareView.showFailure()
        }
    }

    /// Copies one generated file and reports what the pasteboard actually did.
    private func copy(_ asset: PetShareAssetKind) {
        guard let assets else { return }
        let url = asset == .video ? assets.movieURL : assets.spriteURL
        let copied = (try? Data(contentsOf: url, options: .mappedIfSafe)).map { data in
            if asset == .video {
                guard let published = effects.publishMovie(data, "WaddlyShare.mp4") else { return false }
                return effects.copyMovie(data, published)
            }
            return effects.copyImage(data)
        } ?? false
        copyOutcome[asset] = copied
        shareView.showCopyResult(copyText(for: asset, copied: copied), failed: !copied, for: asset)
    }

    private func copyText(for asset: PetShareAssetKind, copied: Bool) -> String {
        guard copied else { return localization.string(for: .shareCopyFailed) }
        return localization.string(for: asset == .video ? .shareCopiedVideo : .shareCopiedImage)
    }

    /// Opens the X post composer with a hashtag only; the user's post text remains theirs.
    private func openX() {
        guard let url = Self.xPostURL(),
              effects.openURL(url)
        else {
            composerOpenFailed = true
            shareView.showXOpenFailure(localization.string(for: .shareOpenXFailed))
            return
        }
        composerOpenFailed = false
        shareView.showXOpenFailure(nil)
    }

    static func xPostURL() -> URL? {
        var components = URLComponents(string: "https://twitter.com/intent/tweet")
        components?.queryItems = [
            URLQueryItem(name: "hashtags", value: "ShareMyWaddly")
        ]
        return components?.url
    }
}
