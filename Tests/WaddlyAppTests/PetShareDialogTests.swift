import AppKit
import AVKit
import Testing
@testable import WaddlyApp

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
