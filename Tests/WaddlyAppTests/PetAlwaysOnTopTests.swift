import AppKit
import Testing
@testable import WaddlyApp

/// Issue #201: the pet panel is always on top of ordinary app windows, including other apps'
/// floating panels. Putting it back in front must never activate Waddly or take a click.
@Suite(.serialized) @MainActor struct PetAlwaysOnTopTests {
    /// The Space behaviour the pet keeps. `.fullScreenAuxiliary` is deliberately absent: a fullscreen
    /// app covers the pet, as recorded in the README and DESIGN.
    private let expectedCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .stationary,
        .ignoresCycle
    ]

    // MARK: - Window level

    @Test func buildingThePanelFloatsAboveOtherWindows() throws {
        let isolated = try IsolatedApp()
        defer { isolated.close() }

        isolated.app.buildPanel()

        expectAlwaysOnTop(isolated.app)
    }

    /// Every reveal path reapplies the level, so a stale value cannot survive showing the pet again.
    @Test func revealsReapplyTheWindowLevel() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        app.panel.alphaValue = 0
        try await app.persistPetImages(fixture.exampleImages())

        let revealPaths: [() -> Void] = [
            { app.bringPetToFront() },
            { app.imageSetDidChange() },
            { app.revealPet() }
        ]
        for reveal in revealPaths {
            drift(app)
            reveal()
            expectAlwaysOnTop(app)
        }

        app.presenter.hide(app.panel)
        #expect(!app.panel.isVisible)
        app.revealPet()
        #expect(app.panel.isVisible)
        expectAlwaysOnTop(app)
    }

    /// The setup handover's fade is a second reveal seam and has to reapply the level as well.
    @Test func fadeInRevealReappliesTheWindowLevel() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let isolated = try IsolatedApp()
        defer { isolated.close() }
        let app = isolated.app
        app.buildPanel()
        try await app.persistPetImages(fixture.exampleImages())

        drift(app)
        app.revealPetOnDesktop()
        #expect(app.panel.isVisible)
        expectAlwaysOnTop(app)

        // Pin the fade seam itself even when Reduce Motion routes the desktop reveal elsewhere.
        drift(app)
        app.revealPetFadingIn()
        expectAlwaysOnTop(app)
    }

    // MARK: - Keeping the pet in front

    /// Another app activating or a Space switch puts the pet back above that app's floating panels,
    /// without activating Waddly: ordering is the non-activating presenter's reveal.
    @Test func workspaceChangesReorderThePetWithoutActivating() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let recorder = RevealRecorder()
        let isolated = try IsolatedApp(presenter: recorder.presenter)
        defer { isolated.close() }
        let app = isolated.app
        app.buildPanel()
        app.startKeepingPetInFront()
        try await app.persistPetImages(fixture.exampleImages())
        // Other processes can activate during a test run, so count the reveals this test causes
        // rather than asserting an absolute total.
        var baseline = recorder.reveals

        post(NSWorkspace.didActivateApplicationNotification)
        #expect(recorder.reveals >= baseline + 1)
        // The activating app may order its own floating panel after the notification, so the pet
        // re-orders once more when the activation settles.
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.reveals >= baseline + 2)
        #expect(recorder.activations == 0)

        baseline = recorder.reveals
        post(NSWorkspace.activeSpaceDidChangeNotification)
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.reveals >= baseline + 2)

        // The re-ordering path also repairs a stale level, because revealPet goes through the seam.
        drift(app)
        post(NSWorkspace.didActivateApplicationNotification)
        try await Task.sleep(for: .milliseconds(400))
        expectAlwaysOnTop(app)
    }

    /// Setup must not flash an empty pet panel, and the observers are idempotent and removable.
    @Test func reorderingIsSkippedWithoutAPetAndStopsWithItsObservers() async throws {
        let recorder = RevealRecorder()
        let isolated = try IsolatedApp(presenter: recorder.presenter)
        defer { isolated.close() }
        let app = isolated.app
        app.buildPanel()

        app.startKeepingPetInFront()
        app.startKeepingPetInFront()
        post(NSWorkspace.didActivateApplicationNotification)
        try await Task.sleep(for: .milliseconds(300))
        #expect(recorder.reveals == 0)
        #expect(!app.panel.isVisible)

        app.stopKeepingPetInFront()
        post(NSWorkspace.didActivateApplicationNotification)
        #expect(recorder.reveals == 0)
    }

    // MARK: - Helpers

    private func expectAlwaysOnTop(_ app: AppDelegate) {
        #expect(app.panel.level == .floating)
        #expect(app.panel.collectionBehavior == expectedCollectionBehavior)
        #expect(!app.panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    private func drift(_ app: AppDelegate) {
        app.panel.level = .normal
        app.panel.collectionBehavior = []
    }

    private func post(_ name: NSNotification.Name) {
        NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
    }
}

/// An app with its own defaults suite and image directory, so the suite never reads or writes the
/// developer's real preferences, plus the cleanup every test needs.
@MainActor private final class IsolatedApp {
    let app: AppDelegate
    private let domain: String
    private let defaults: UserDefaults
    private let directory: URL

    init(presenter: WindowPresenter = .invisible) throws {
        domain = "WaddlyTests.alwaysOnTop.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: domain))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let settings = AppSettings(defaults: defaults)
        settings.registerDefaults()
        app = AppDelegate(settings: settings, presenter: presenter)
        app.petImagesDirectoryURL = directory
    }

    func close() {
        app.stopKeepingPetInFront()
        app.imageStore.beginShutdown()
        app.animationController.shutdown()
        app.setupWizardController?.close()
        app.characterImportWindowController?.close()
        app.monitor.stop()
        app.panel.close()
        defaults.removePersistentDomain(forName: domain)
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            Issue.record("Could not remove the temporary directory: \(error)")
        }
    }
}

/// Counts how the app reaches the screen. A real order-front would paint a window during the test
/// run, so the recorder stands in for it and only records the calls.
@MainActor private final class RevealRecorder {
    var reveals = 0
    var fadedReveals = 0
    var activations = 0

    lazy var presenter = WindowPresenter(
        activate: { [weak self] in
            self?.activations += 1
        },
        reveal: { [weak self] _ in
            self?.reveals += 1
        },
        focus: { _ in },
        hide: { _ in },
        revealFadingIn: { [weak self] _, _ in
            self?.fadedReveals += 1
        },
        presentAlert: { _, _, completion in
            completion(.OK)
        }
    )
}
