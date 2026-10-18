import AppKit
import AVKit
import Foundation
import os
import Testing
@testable import WaddlyApp
import WaddlyCore

@Test @MainActor func openingShareDialogPreparesMovieAndSpriteForPreview() async throws {
    _ = NSApplication.shared
    let suiteName = "WaddlyTests.share-dialog.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let app = makeTestApp(settings: AppSettings(defaults: defaults))
    app.importedImages = try SetupWizardFixture.sheetImages()

    app.showPetShare()
    let window = try #require(app.shareWindowController?.window)
    defer { app.shareWindowController?.close() }
    #expect(window.isVisible)
    #expect(window.appearance == nil)
    let contentView = try #require(window.contentView)
    try assertShareDialogUsesDarkAppearance(window: window, contentView: contentView)
    let postRow = try #require(descendants(of: contentView).first {
        $0.identifier?.rawValue == "share.postRow"
    })
    #expect(postRow.frame.height == 52)
    let identity = try #require(descendants(of: postRow).first {
        $0.identifier?.rawValue == "share.xIdentity"
    })
    #expect(abs(identity.frame.midX - postRow.bounds.midX) <= 1)
    #expect((identity as? NSStackView)?.spacing == 6)
    let logo = try #require(descendants(of: identity).first {
        $0.identifier?.rawValue == "share.xLogo"
    })
    #expect(logo.frame.width == 32)
    #expect(logo.frame.width == logo.frame.height)
    #expect(logo.frame.midY == identity.bounds.midY)
    #expect(logo.gestureRecognizers.contains { $0 is NSClickGestureRecognizer })
    let label = try #require(descendants(of: identity).first { $0 is NSTextField })
    #expect(label.gestureRecognizers.contains { $0 is NSClickGestureRecognizer })

    for _ in 0 ..< 400 {
        let views = descendants(of: contentView)
        let moviePreview = views.first { $0.identifier?.rawValue == "share.moviePreview" }
        let sprite = views.first { $0.identifier?.rawValue == "share.spritePreview" } as? NSImageView
        let playButton = views.compactMap { $0 as? NSButton }.first { $0.title == "▶" }
        if let moviePreview, sprite?.image != nil, let playButton {
            #expect(!moviePreview.subviews.contains { $0 is AVPlayerView })
            #expect(moviePreview.subviews.compactMap { $0 as? NSImageView }.first?.image != nil)
            #expect(playButton.frame.midY < moviePreview.frame.midY)
            playButton.performClick(nil)
            #expect(moviePreview.subviews.compactMap { $0 as? AVPlayerView }.first?.player != nil)
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("share dialog did not prepare both preview assets")
}

@Test @MainActor func closingTheShareWindowCancelsPendingGeneration() async throws {
    _ = NSApplication.shared
    let suiteName = "WaddlyTests.share-close.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
    let localization = LocalizationController(settings: AppSettings(defaults: defaults), resources: resources)
    let generationStarted = SharedValue<Bool>()
    let generationToken = SharedValue<PetShareExportCancellation>()
    let images = try SetupWizardFixture.sheetImages()
    let controller = PetShareWindowController(
        images: images,
        localization: localization
    ) { _, _, cancellation in
        generationToken.store(cancellation)
        generationStarted.store(true)
        // Stands in for the encoder: it only returns once closing the dialog cancels generation.
        let deadline = Date().addingTimeInterval(5)
        while !cancellation.isCancelled, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw PetShareExportError.cancelled
    }
    var didClose = false
    controller.onClose = { didClose = true }

    // The window stays off screen: showing it activates the app, and a later test in this headless host
    // then loses the process. Closing it still delivers `windowWillClose`, which is what this covers.
    controller.prepareAssets()
    #expect(await waitFor({ generationStarted.current == true }, within: 5))

    controller.close()

    // Closing must cancel the token the pending generation observes, not wait for it to finish.
    #expect(generationToken.current?.isCancelled == true)
    #expect(didClose)
}

@Test @MainActor func aFailedGenerationLeavesTheMoviesCleanupToTheExport() throws {
    let images = try SetupWizardFixture.sheetImages()
    let movie = SharedValue<URL>()

    #expect(throws: PetShareExportError.timedOut) {
        // A stalled export gives up while its writer may still own the movie; the caller must not delete it.
        _ = try PetShareAssets.make(from: images, cancellation: PetShareExportCancellation()) { _, url, _ in
            movie.store(url)
            try Data("partial".utf8).write(to: url)
            throw PetShareExportError.timedOut
        }
    }

    let movieURL = try #require(movie.current)
    let spriteURL = movieURL.deletingPathExtension().appendingPathExtension("png")
    defer { try? FileManager.default.removeItem(at: movieURL) }
    #expect(!FileManager.default.fileExists(atPath: spriteURL.path))
    #expect(FileManager.default.fileExists(atPath: movieURL.path))
}

@Test @MainActor func xPostURLIncludesReminderAndShareHashtag() throws {
    let reminder = "動画と画像をコピーしてポストに添付してください"
    let url = try #require(PetShareWindowController.xPostURL(text: reminder))
    let queryItems = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

    #expect(queryItems.first { $0.name == "text" }?.value == reminder)
    #expect(queryItems.first { $0.name == "hashtags" }?.value == "ShareMyWaddly")
}

@Test @MainActor func openShareDialogRefreshesLabelsWhenLanguageChanges() throws {
    _ = NSApplication.shared
    let suiteName = "WaddlyTests.share-dialog-localization.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
    let localization = LocalizationController(settings: settings, resources: resources)
    localization.changeLanguage(.japanese)
    let view = PetShareDialogView(localization: localization)
    let copyButtons = SetupWizardFixture.descendants(of: view).compactMap { $0 as? NSButton }
        .filter { $0.title == "コピー" }

    #expect(copyButtons.count == 2)
    localization.changeLanguage(.english)
    view.refreshLocalization()
    #expect(copyButtons.allSatisfy { $0.title == "Copy" })
}

@MainActor private func assertShareDialogUsesDarkAppearance(window: NSWindow, contentView: NSView) throws {
    window.appearance = NSAppearance(named: .darkAqua)
    contentView.layoutSubtreeIfNeeded()
    let card = try #require(contentView.subviews.compactMap { $0 as? NSStackView }.first?.arrangedSubviews.first)
    let cardBackground = try #require(card.layer?.backgroundColor)
    let cardColor = try #require(NSColor(cgColor: cardBackground))
    let rgbColor = try #require(cardColor.usingColorSpace(.deviceRGB))
    #expect(rgbColor.redComponent < 0.5)
}

@MainActor private func descendants(of view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants(of:))
}

/// Yields the main actor while polling, so the controller's detached generation task can make progress.
@MainActor private func waitFor(_ condition: () -> Bool, within seconds: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// A value a detached task can store and the main actor can read.
private final class SharedValue<Value: Sendable>: Sendable {
    private let value = OSAllocatedUnfairLock<Value?>(initialState: nil)

    var current: Value? {
        value.withLock { $0 }
    }

    func store(_ newValue: Value) {
        value.withLock { $0 = newValue }
    }
}
