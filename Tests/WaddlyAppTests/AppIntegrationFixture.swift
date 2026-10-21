import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Shared app fixture for integration-style tests: an isolated `AppDelegate` with its own defaults
/// suite and temporary image directory.
@MainActor final class AppIntegrationFixture {
    let domain = "WaddlyTests.integration.\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let app: AppDelegate
    let exampleURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("assets/examples/nyatinte-bot-3x3.png")

    init() throws {
        _ = NSApplication.shared
        defaults = try #require(UserDefaults(suiteName: domain))
        app = AppDelegate(settings: AppSettings(defaults: defaults))
        app.settings.registerDefaults()
        app.petImagesDirectoryURL = directory
        app.buildPanel()
        app.buildMenu()
    }

    /// The nine frame images alone, without sheet-source editing metadata, so fixture saves stay a
    /// plain nine-file frame set.
    func exampleImages() throws -> PetImageSet {
        let images = try #require(PetSpriteSheetImporter.frames(from: Data(contentsOf: exampleURL)))
        var plain = PetImageSet()
        for category in PetImageCategory.allCases {
            plain[category] = images[category]
        }
        return plain
    }

    func savedData() throws -> [String: Data] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: urls.map { try ($0.lastPathComponent, Data(contentsOf: $0)) })
    }

    /// Only the frame files, so a manifest write does not look like a rewritten frame.
    func frameData() throws -> [String: Data] {
        try savedData().filter { $0.key.hasSuffix(".png") }
    }

    func manifest() throws -> [String: [String]]? {
        try PetImageStorage(directory: directory).readManifest()
    }

    func close() {
        app.imageStore.beginShutdown()
        app.animationController.shutdown()
        app.setupWizardController?.close()
        app.characterImportWindowController?.close()
        // Closing setup can start monitoring; stop it after closing all windows.
        app.monitor.stop()
        app.panel.close()
        NSStatusBar.system.removeStatusItem(app.statusItem)
        defaults.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor func waitForSheet(_ app: AppDelegate) async throws -> NSWindow {
    for _ in 0 ..< 200 {
        if let sheet = app.setupWizardController?.window?.attachedSheet {
            return sheet
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw CocoaError(.userCancelled)
}

/// Validation is what the menu actually asks, so the tests ask it the same way.
@MainActor func editorItem(of app: AppDelegate) throws -> NSMenuItem {
    try #require(menuItems(app.statusMenu).first {
        $0.action == #selector(AppDelegate.showChangeCharacter)
    })
}

@MainActor func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
    menu.items.flatMap { item in [item] + (item.submenu.map(menuItems) ?? []) }
}
