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
    let postButton = try assertShareActionsUseTheDesignSystem(
        in: contentView,
        postLabel: app.localizedString(.shareXCreate)
    )

    for _ in 0 ..< 400 {
        let views = descendants(of: contentView)
        let moviePreview = views.first { $0.identifier?.rawValue == "share.moviePreview" }
        let sprite = views.first { $0.identifier?.rawValue == "share.spritePreview" } as? NSImageView
        let playButton = views.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "share.playButton"
        }
        if let moviePreview, sprite?.image != nil, let playButton {
            #expect(postButton.isEnabled)
            #expect(!moviePreview.subviews.contains { $0 is AVPlayerView })
            #expect(moviePreview.subviews.compactMap { $0 as? NSImageView }.first?.image != nil)
            #expect(playButton.frame.midY < moviePreview.frame.midY)
            try sendTestAction(playButton)
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
        localization: localization,
        effects: PetShareEffects(writeMovie: { _, _, cancellation in
            generationToken.store(cancellation)
            generationStarted.store(true)
            // Stands in for the encoder: it only returns once closing the dialog cancels generation.
            let deadline = Date().addingTimeInterval(5)
            while !cancellation.isCancelled, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            throw PetShareExportError.cancelled
        })
    )
    var didClose = false
    controller.onClose = { didClose = true }

    // Presentation is covered above. This test only needs `windowWillClose` to cancel the pending
    // export; preparing without showing keeps that cancellation assertion independent of presentation.
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

@Test @MainActor func xPostURLLeavesThePostTextEmptyAndCarriesOnlyTheShareHashtag() throws {
    let url = try #require(PetShareWindowController.xPostURL())
    let queryItems = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

    #expect(queryItems.contains { $0.name == "text" } == false)
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
        .filter { $0.identifier?.rawValue.hasPrefix("share.copy") == true }

    #expect(copyButtons.count == 2)
    localization.changeLanguage(.english)
    view.refreshLocalization()
    #expect(copyButtons.first { $0.identifier?.rawValue == "share.copyVideo" }?.title == "Copy video")
    #expect(copyButtons.first { $0.identifier?.rawValue == "share.copyImage" }?.title == "Copy image")
}

@MainActor private func assertShareActionsUseTheDesignSystem(
    in contentView: NSView,
    postLabel: String
) throws -> NSButton {
    contentView.layoutSubtreeIfNeeded()
    let postRow = try #require(descendants(of: contentView).first {
        $0.identifier?.rawValue == "share.postRow"
    })
    #expect(postRow.frame.height == LayoutMetrics.actionHeight)
    let postButton = try #require(descendants(of: postRow).first {
        $0.identifier?.rawValue == "share.postButton"
    } as? NSButton)
    #expect(postButton.frame.height == LayoutMetrics.actionHeight)
    #expect(abs(postButton.frame.midX - postRow.bounds.midX) <= 1)
    #expect(postButton.image?.isTemplate == true)
    #expect((postButton.image?.size.width ?? 0) > (postButton.image?.size.height ?? 0))
    #expect(postButton.action != nil)
    #expect(postButton.accessibilityLabel() == postLabel)
    #expect(descendants(of: contentView).contains { ($0 as? NSBox)?.boxType == .separator })
    for identifier in ["share.copyVideo", "share.copyImage"] {
        let copy = try #require(descendants(of: contentView).first {
            $0.identifier?.rawValue == identifier
        } as? NSButton)
        #expect(copy.frame.height == LayoutMetrics.actionHeight, "\(identifier)")
    }
    return postButton
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

@Test @MainActor func brandTitleDrawingKeepsTheNativeVerticalCenter() {
    let frame = NSRect(x: 10, y: 0, width: 120, height: LayoutMetrics.actionHeight)
    let title = ShareActionButtonCell.centeredTitleRect(for: NSSize(width: 60, height: 16), in: frame)
    #expect(abs(title.midY - frame.midY) <= 0.5)
    #expect(abs(title.midX - frame.midX) <= 0.5)
    #expect(title.height == 16)
}
