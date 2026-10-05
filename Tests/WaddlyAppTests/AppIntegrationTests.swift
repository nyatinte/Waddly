import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct AppIntegrationTests {
    @Test func imagesSurviveEditsAndReloadWithoutRewritingRetainedFrames() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let app = fixture.app
        let images = try fixture.exampleImages()
        try await app.persistPetImages(images, resetActivity: true)
        let original = app.settings.petImageFiles
        let data = try fixture.savedData()
        #expect(app.hasCompletePetImageSet)
        #expect(app.panel.isVisible)
        app.moveImage(from: 0, to: 1, in: .idle)
        await app.pendingImageUpdate?.value
        // moveImage enqueues from its own task; wait for that task to enter the queue.
        for _ in 0 ..< 200 where app.settings.petImageFiles["idle"] == original["idle"] {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(app.settings.petImageFiles["idle"] == original["idle"]?.reversed().map(\.self))
        #expect(try fixture.savedData() == data)
        let removal = try #require(app.removeImage(at: 0, from: .idle))
        await removal.value
        #expect(app.petImages[.idle].count == 1)
        await app.removeImage(at: 0, from: .idle)?.value
        #expect(app.petImages[.idle].count == 1)
        let edited = app.settings.petImageFiles
        app.importedImages = nil
        await app.loadSavedPetImage()
        app.imageSetDidChange()
        #expect(app.hasCompletePetImageSet)
        #expect(app.storedImageFiles == edited)
        #expect(app.petImages[.typing].count == 4)
        #expect(app.petImages[.sleep].count == 2)
        #expect(app.petImages[.enter].count == 1)
        #expect(try fixture.savedData().count == 8)
    }

    @Test func cancelingReplacementAndInvalidImportsPreserveSavedImages() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        let manifest = app.settings.petImageFiles
        let data = try fixture.savedData()
        app.showSetupWizard()
        let replacement = Task { await app.importPetImage(from: fixture.exampleURL) }
        let sheet = try await waitForSheet(app)
        sheet.sheetParent?.endSheet(sheet, returnCode: .alertSecondButtonReturn)
        #expect(await !replacement.value)
        #expect(app.settings.petImageFiles == manifest)
        #expect(try fixture.savedData() == data)
        let invalidURL = fixture.directory.appendingPathComponent("invalid.png")
        try Data("not a PNG".utf8).write(to: invalidURL)
        let invalid = Task { await app.importPetImage(from: invalidURL) }
        let errorSheet = try await waitForSheet(app)
        errorSheet.sheetParent?.endSheet(errorSheet, returnCode: .alertFirstButtonReturn)
        #expect(await !invalid.value)
        #expect(app.settings.petImageFiles == manifest)
        #expect(app.hasCompletePetImageSet)
    }

    @Test func missingSavedFrameDoesNotDeleteOrCommitAPartialManifest() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        let manifest = app.settings.petImageFiles
        let filename = try #require(manifest["enter"]?.first)
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent(filename))
        app.importedImages = nil
        await app.loadSavedPetImage()
        app.imageSetDidChange()
        #expect(!app.hasCompletePetImageSet)
        #expect(!app.panel.isVisible)
        #expect(app.settings.petImageFiles == manifest)
        #expect(try fixture.savedData().count == 8)
    }

    @Test func menuCommandsUpdatePreferencesAndKeepAnEntryPointVisible() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let app = fixture.app
        app.buildMenu()
        let size = try #require(menuItems(app.statusMenu).first {
            $0.action == NSSelectorFromString("setSize:") && $0.tag == 320
        })
        #expect(try NSApp.sendAction(#require(size.action), to: size.target, from: size))
        #expect(app.settings.displaySize == 320)
        #expect(app.panel.frame.width == 320)
        #expect(size.state == .on)
        let motion = try #require(menuItems(app.statusMenu).first {
            $0.action == NSSelectorFromString("setTypingMotion:") && $0.tag == TypingMotion.off.rawValue
        })
        #expect(try NSApp.sendAction(#require(motion.action), to: motion.target, from: motion))
        #expect(app.typingMotion == .off)
        #expect(motion.state == .on)
        app.settings.showInDock = false
        app.settings.showInMenuBar = false
        app.settings.ensurePresenceIsVisible()
        #expect(app.settings.showInDock)
        #expect(!app.settings.showInMenuBar)
        app.settings.setupWizardSeen = true
        app.showSetupWizard()
        app.setupWizardController?.close()
        #expect(!app.settings.setupWizardSeen)
    }

    @Test(arguments: [false, true])
    func dockReopenRestoresControlsWithoutAMenuBar(hasImages: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let app = fixture.app
        app.settings.showInMenuBar = false
        if hasImages {
            try await app.persistPetImages(fixture.exampleImages())
        }
        let delegate: any NSApplicationDelegate = app
        let handled = delegate.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: hasImages)
        #expect(handled == false)
        if hasImages {
            #expect(app.imageSettingsWindow?.isVisible == true)
        } else {
            #expect(app.setupWizardController?.window?.isVisible == true)
        }
    }

    @Test func dockReopenKeepsAnOpenSetupWizard() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.showSetupWizard()
        let wizard = try #require(app.setupWizardController)
        let delegate: any NSApplicationDelegate = app
        #expect(delegate.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: true) == false)
        #expect(app.setupWizardController === wizard)
        #expect(wizard.window?.isVisible == true)
        #expect(app.imageSettingsWindow == nil)
    }

    private func waitForSheet(_ app: AppDelegate) async throws -> NSWindow {
        for _ in 0 ..< 200 {
            if let sheet = app.setupWizardController?.window?.attachedSheet {
                return sheet
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.userCancelled)
    }

    private func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(menuItems) ?? []) }
    }

    @MainActor private final class Fixture {
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
        }

        func exampleImages() throws -> PetImageSet {
            try #require(PetSpriteSheetImporter.frames(from: Data(contentsOf: exampleURL)))
        }

        func savedData() throws -> [String: Data] {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            return try Dictionary(uniqueKeysWithValues: urls.map { try ($0.lastPathComponent, Data(contentsOf: $0)) })
        }

        func close() {
            app.isShuttingDown = true
            app.animationController.shutdown()
            app.setupWizardController?.close()
            app.imageSettingsWindow?.close()
            // Closing setup can start monitoring; stop it after closing all windows.
            app.monitor.stop()
            app.panel.close()
            NSStatusBar.system.removeStatusItem(app.statusItem)
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
