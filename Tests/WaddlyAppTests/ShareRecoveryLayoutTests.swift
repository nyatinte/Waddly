import AppKit
import Testing
@testable import WaddlyApp

@Test @MainActor func shareRecoveryInstructionsFitWithoutMovingActions() throws {
    _ = NSApplication.shared
    let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
    for language in [AppLanguage.english, .japanese] {
        let suiteName = "WaddlyTests.share-layout.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.appLanguage = language
        let localization = LocalizationController(settings: settings, resources: resources)
        let view = PetShareDialogView(localization: localization)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 380),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.showAssets(spriteURL: URL(fileURLWithPath: "/nonexistent.png"),
                        movieURL: URL(fileURLWithPath: "/nonexistent.mp4"), moviePoster: nil)
        view.layoutSubtreeIfNeeded()
        let descendants = SetupWizardFixture.descendants(of: view)
        let buttons = try ["share.copyVideo", "share.copyImage", "share.postButton"].map { id in
            try #require(descendants.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == id })
        }
        let originalFrames = buttons.map(\.frame)
        let copy = localization.string(for: .shareCopyFailed)
        let composer = localization.string(for: .shareOpenXFailed)
        view.showCopyResult(copy, failed: true, for: .video)
        view.showCopyResult(copy, failed: true, for: .image)
        view.showXOpenFailure(composer)
        view.layoutSubtreeIfNeeded()
        #expect(buttons.map(\.frame) == originalFrames)
        let messages = [("share.videoStatus", copy), ("share.imageStatus", copy), ("share.postStatus", composer)]
        for (id, expected) in messages {
            let label = try #require(descendants.compactMap { $0 as? NSTextField }
                .first { $0.identifier?.rawValue == id })
            try assertRecoveryFits(label, expected: expected, context: "\(language) \(id)")
        }
        view.showWorking()
        view.layoutSubtreeIfNeeded()
        #expect(buttons.map(\.frame) == originalFrames)
        window.close()
    }
}

@MainActor private func assertRecoveryFits(_ label: NSTextField, expected: String, context: String) throws {
    let cell = try #require(label.cell)
    #expect(label.stringValue == expected)
    #expect(!label.isHiddenOrHasHiddenAncestor)
    #expect(label.lineBreakMode == .byWordWrapping)
    let drawingRect = cell.drawingRect(forBounds: label.bounds)
    let font = try #require(label.font)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    let needed = (expected as NSString).boundingRect(
        with: NSSize(width: drawingRect.width, height: 1000),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font, .paragraphStyle: paragraph]
    )
    #expect(ceil(needed.height) <= drawingRect.height + 1, "\(context): \(needed) in \(drawingRect)")
}
