import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct AppIntegrationTests {
    @Test func imagesSurviveEditsAndReloadWithoutRewritingRetainedFrames() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        let images = try fixture.exampleImages()
        try await app.persistPetImages(images, resetActivity: true)
        let original = app.settings.petImageFiles
        let data = try fixture.frameData()
        #expect(app.hasCompletePetImageSet)
        #expect(app.panel.isVisible)
        await app.moveImage(from: 0, to: 1, in: .idle)?.value
        #expect(app.settings.petImageFiles["idle"] == original["idle"]?.reversed().map(\.self))
        // A reorder rewrites only the manifest; the frame files themselves stay untouched.
        #expect(try fixture.frameData() == data)
        #expect(try fixture.manifest() == app.settings.petImageFiles)
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
        #expect(try fixture.frameData().count == 8)
    }

    @Test func cancelingReplacementAndInvalidImportsPreserveSavedImages() async throws {
        let fixture = try AppIntegrationFixture()
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
        let fixture = try AppIntegrationFixture()
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
        // A referenced frame that is gone blocks edits instead of committing a reduced manifest.
        #expect(app.imageLoadFailed)
        #expect(try fixture.frameData().count == 8)
        #expect(try fixture.manifest() == manifest)
    }

    @Test func menuCommandsUpdatePreferencesAndKeepAnEntryPointVisible() throws {
        let fixture = try AppIntegrationFixture()
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
        #expect(app.setupWizardController == nil)
    }

    @Test(arguments: [false, true])
    func dockReopenRestoresControlsWithoutAMenuBar(hasImages: Bool) async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        app.settings.showInMenuBar = false
        if hasImages {
            try await app.persistPetImages(fixture.exampleImages())
        }
        let delegate: any NSApplicationDelegate = app
        let handled = delegate.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: hasImages)
        #expect(handled == false)
        #expect(app.characterImportWindowController?.window?.isVisible != true)
        #expect(app.setupWizardController?.window?.isVisible == true)
    }

    /// The animation editor is menu-only. Even after setup, the Dock icon must not open it.
    @Test func dockReopenNeverOpensChangeCharacterAfterSetup() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.settings.setupWizardSeen = true
        app.settings.setupStep = nil
        app.settings.showInMenuBar = false

        let delegate: any NSApplicationDelegate = app
        #expect(delegate.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: true) == false)
        #expect(app.characterImportWindowController?.window?.isVisible != true)
        #expect(app.panel.isVisible == true)
        // The menu stays the deliberate route to the editor once setup is finished. Opening the menu
        // is when the app re-evaluates what it offers.
        app.menuWillOpen(app.statusMenu)
        #expect(try app.validateMenuItem(editorItem(of: app)))
    }

    /// Re-showing an already open guide must not recenter it: the app's own move would look like a
    /// user drag to `GuideFollowing` and stop the guide from following System Settings (#79).
    @Test func reShowingAnOpenGuideKeepsItFollowing() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.settings.setupWizardSeen = true
        app.settings.setupStep = SetupWizardController.Step.monitoring.rawValue
        app.showSetupWizard()
        let wizard = try #require(app.setupWizardController)
        // The manual fallback is the same guiding phase without opening System Settings in tests.
        app.permissionService.toggleManualSteps()
        #expect(wizard.isShowingGuide)

        let parked = NSPoint(x: 120, y: 80)
        wizard.recordProgrammaticGuideOrigin(parked)
        wizard.window?.setFrameOrigin(parked)
        #expect(wizard.isFollowingSystemSettings)

        app.showSetupWizard()
        wizard.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        #expect(wizard.isFollowingSystemSettings)
        #expect(wizard.window?.frame.origin == parked)

        wizard.window?.orderOut(nil)
        app.showSetupWizard()
        wizard.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        #expect(wizard.isFollowingSystemSettings)

        wizard.window?.setFrameOrigin(NSPoint(x: 300, y: 220))
        wizard.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        #expect(!wizard.isFollowingSystemSettings)
    }

    /// Leaving setup part-way keeps the saved step, so the Dock icon resumes it.
    @Test func dockReopenResumesSetupWhenItWasLeftUnfinished() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.settings.setupWizardSeen = true
        app.settings.setupStep = SetupWizardController.Step.monitoring.rawValue
        app.settings.showInMenuBar = false

        let delegate: any NSApplicationDelegate = app
        #expect(delegate.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: true) == false)
        #expect(app.characterImportWindowController?.window?.isVisible != true)
        #expect(app.setupWizardController?.window?.isVisible == true)
        #expect(app.setupWizardController?.currentStep == .monitoring)
        app.menuWillOpen(app.statusMenu)
        #expect(try !app.validateMenuItem(editorItem(of: app)))
    }

    /// Setup opens on launch only while it is unfinished: a configured user with a leftover step
    /// (for example, after closing the guide early) must not get setup back on the next launch.
    @Test(arguments: LaunchCase.all)
    func launchReopensSetupUntilItIsFinished(scenario: LaunchCase) async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        if scenario.hasImages {
            try await app.persistPetImages(fixture.exampleImages())
        }
        app.settings.setupWizardSeen = scenario.seen
        app.settings.setupStep = scenario.step

        #expect(app.shouldOpenSetupOnLaunch == scenario.expectsSetupOnLaunch, "\(scenario.name)")
        #expect(app.isSetupComplete == scenario.isComplete, "\(scenario.name)")
    }

    @Test func dockReopenKeepsAnOpenSetupWizard() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.showSetupWizard()
        let wizard = try #require(app.setupWizardController)
        let delegate: any NSApplicationDelegate = app
        #expect(delegate.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: true) == false)
        #expect(app.setupWizardController === wizard)
        #expect(wizard.window?.isVisible == true)
        #expect(app.characterImportWindowController == nil)
    }
}

/// The launch cases, named so a failure says which state broke.
struct LaunchCase: Sendable {
    let name: String
    let hasImages: Bool
    let seen: Bool
    let step: Int?
    let expectsSetupOnLaunch: Bool
    let isComplete: Bool

    static let all: [LaunchCase] = [
        LaunchCase(
            name: "nothing yet",
            hasImages: false,
            seen: false,
            step: nil,
            expectsSetupOnLaunch: true,
            isComplete: false
        ),
        LaunchCase(
            name: "no images",
            hasImages: false,
            seen: true,
            step: nil,
            expectsSetupOnLaunch: true,
            isComplete: false
        ),
        LaunchCase(
            name: "images, never finished",
            hasImages: true,
            seen: false,
            step: nil,
            expectsSetupOnLaunch: true,
            isComplete: false
        ),
        LaunchCase(
            name: "images, closed the guide early",
            hasImages: true,
            seen: true,
            step: SetupWizardController.Step.monitoring.rawValue,
            expectsSetupOnLaunch: false,
            isComplete: false
        ),
        LaunchCase(
            name: "finished",
            hasImages: true,
            seen: true,
            step: nil,
            expectsSetupOnLaunch: false,
            isComplete: true
        )
    ]
}
