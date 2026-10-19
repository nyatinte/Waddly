import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Renders the share dialog to `docs/images/share`.
///
/// The PNGs are committed design evidence for the share redesign, so this runs only on demand:
/// `WADDLY_CAPTURE_SHARE=1 ./macos/test.sh --filter ShareSnapshotTests`.
///
/// The window is deliberately visible (`WindowPresenter.live`, parked far off screen) because the rest
/// of the suite renders windows transparent. Nothing here is an operating-system screenshot and nothing
/// was checked by hand: the same AppKit views the app builds are drawn into a bitmap with the repository's
/// example sprite sheet and an English/Japanese, light/dark preference.
@Test(.enabled(if: ProcessInfo.processInfo.environment["WADDLY_CAPTURE_SHARE"] != nil))
@MainActor func captureShareDialogStates() throws {
    _ = NSApplication.shared
    let output = SetupWizardFixture.root().appendingPathComponent("docs/images/share", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    for (language, name) in [(AppLanguage.english, "en"), (.japanese, "ja")] {
        for (appearance, appearanceName) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            let data = try captureShareDialog(state: .ready, language: language, appearance: appearance)
            try data.write(to: output.appendingPathComponent("dialog-after-\(name)-\(appearanceName).png"))
        }
    }
    for (state, name) in [
        (ShareSnapshotState.hover, "hover"),
        (.retryHover, "retry-hover"),
        (.working, "working"),
        (.failed, "failed"),
        (.copied, "copied"),
        (.copyFailed, "copy-failed"),
        (.composerFailed, "composer-failed")
    ] {
        let data = try captureShareDialog(state: state, language: .english, appearance: .aqua)
        try data.write(to: output.appendingPathComponent("state-\(name)-en-light.png"))
    }
    let japaneseFailure = try captureShareDialog(state: .failed, language: .japanese, appearance: .darkAqua)
    try japaneseFailure.write(to: output.appendingPathComponent("state-failed-ja-dark.png"))
}

private enum ShareSnapshotState: Equatable {
    case ready
    case hover
    case retryHover
    case working
    case failed
    case copied
    case copyFailed
    case composerFailed
}

/// One dialog with generated assets, ready to be put into a state and drawn.
@MainActor
private struct ShareSnapshotFixture {
    let suiteName: String
    let localization: LocalizationController
    let controller: PetShareWindowController
    let view: PetShareDialogView
    let assets: (spriteURL: URL, movieURL: URL)
    let poster: NSImage?

    /// The repository's example sheet, written where the dialog can preview it like a generated export.
    private static func writeAssets(from images: PetImageSet) throws -> (spriteURL: URL, movieURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaddlySnapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let spriteURL = directory.appendingPathComponent("pet-sprite.png")
        let movieURL = directory.appendingPathComponent("pet-animation.mp4")
        try #require(PetShareExporter.spriteSheetPNG(from: images)).write(to: spriteURL)
        // The dialog previews the poster frame, so a placeholder stands in for the encoded movie.
        try Data("movie".utf8).write(to: movieURL)
        return (spriteURL, movieURL)
    }

    init(language: AppLanguage) throws {
        let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
        suiteName = "WaddlyTests.share-snapshot.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = AppSettings(defaults: defaults)
        settings.appLanguage = language
        localization = LocalizationController(settings: settings, resources: resources)
        let images = try SetupWizardFixture.sheetImages()
        let writer: PetShareWindowController.MovieWriter = { _, url, _ in
            try Data("movie".utf8).write(to: url)
        }
        controller = PetShareWindowController(
            images: images,
            localization: localization,
            presenter: .live,
            effects: PetShareEffects(writeMovie: writer)
        )
        view = try #require(controller.window?.contentView as? PetShareDialogView)
        assets = try Self.writeAssets(from: images)
        poster = images[.idle].first
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: assets.spriteURL.deletingLastPathComponent())
        controller.close()
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}

@MainActor private func captureShareDialog(
    state: ShareSnapshotState,
    language: AppLanguage,
    appearance: NSAppearance.Name
) throws -> Data {
    let fixture = try ShareSnapshotFixture(language: language)
    defer { fixture.cleanUp() }
    try apply(
        state,
        to: fixture.view,
        localization: fixture.localization,
        poster: fixture.poster,
        assets: fixture.assets
    )
    return try render(fixture.controller, appearance: appearance)
}

@MainActor private func apply(
    _ state: ShareSnapshotState,
    to view: PetShareDialogView,
    localization: LocalizationController,
    poster: NSImage?,
    assets: (spriteURL: URL, movieURL: URL)
) throws {
    switch state {
    case .working:
        view.showWorking()
    case .failed, .retryHover:
        view.showFailure()
        if state == .retryHover {
            let retry = try #require(SetupWizardFixture.descendants(of: view).compactMap { $0 as? ShareActionButton }
                .first { $0.identifier?.rawValue == "share.retry" })
            retry.setHovered(true)
        }
    case .ready, .hover, .copied, .copyFailed, .composerFailed:
        view.showAssets(spriteURL: assets.spriteURL, movieURL: assets.movieURL, moviePoster: poster)
        try applyOutcome(state, to: view, localization: localization)
    }
}

@MainActor private func applyOutcome(
    _ state: ShareSnapshotState,
    to view: PetShareDialogView,
    localization: LocalizationController
) throws {
    if state == .hover {
        let post = try #require(SetupWizardFixture.descendants(of: view).compactMap { $0 as? ShareActionButton }
            .first { $0.identifier?.rawValue == "share.postButton" })
        post.setHovered(true)
    }
    if state == .copied {
        view.showCopyResult(localization.string(for: .shareCopiedVideo), failed: false, for: .video)
    }
    if state == .copyFailed {
        view.showCopyResult(localization.string(for: .shareCopyFailed), failed: true, for: .image)
    }
    if state == .composerFailed {
        view.showXOpenFailure(localization.string(for: .shareOpenXFailed))
    }
}

@MainActor private func render(_ controller: NSWindowController, appearance: NSAppearance.Name) throws -> Data {
    let window = try #require(controller.window)
    window.appearance = NSAppearance(named: appearance)
    window.setContentSize(NSSize(width: 700, height: 410))
    // Deliberately visible and opaque, parked far off screen so the capture cannot cover the desktop.
    window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
    window.makeKeyAndOrderFront(nil)
    let content = try #require(window.contentView)
    // The dialog draws on the window's background, so the capture has to paint it too.
    content.wantsLayer = true
    content.layer?.backgroundColor = shareLayerColor(.windowBackgroundColor, appearance: window.effectiveAppearance)
    content.layoutSubtreeIfNeeded()
    let rep = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
    content.cacheDisplay(in: content.bounds, to: rep)
    window.orderOut(nil)
    controller.close()
    return try #require(rep.representation(using: .png, properties: [:]))
}
