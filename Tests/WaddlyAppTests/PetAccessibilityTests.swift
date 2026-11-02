import AppKit
import Testing
@testable import WaddlyApp

/// Issue #201: the pet window is the app's only always-visible surface, so VoiceOver and
/// accessibility-based tooling have to be able to name it even though the panel is borderless, has
/// no title bar, and never becomes key.
@Suite(.serialized) @MainActor struct PetAccessibilityTests {
    private struct Expected {
        let windowTitle: String
        let petLabel: String
        let petHelp: String
    }

    private let expectedEnglish = Expected(
        windowTitle: "Waddly pet window",
        petLabel: "Waddly pet",
        petHelp: "Drag to move the pet. Right-click for the menu."
    )

    private let expectedJapanese = Expected(
        windowTitle: "Waddlyのペットウインドウ",
        petLabel: "Waddlyのペット",
        petHelp: "ドラッグでペットを移動できます。右クリックでメニューを開きます。"
    )

    @Test(arguments: [AppLanguage.english, .japanese])
    func petPanelIsNamedForVoiceOver(language: AppLanguage) throws {
        let isolated = try IsolatedPetApp(language: language)
        defer { isolated.close() }

        isolated.app.buildPanel()

        expectAccessibility(of: isolated.app, equals: expected(for: language))
    }

    /// The accessibility strings follow a language change, the same way the rest of the app does.
    @Test func accessibilityLabelsFollowALanguageChange() throws {
        let isolated = try IsolatedPetApp(language: .japanese)
        defer { isolated.close() }
        let app = isolated.app
        app.buildPanel()
        expectAccessibility(of: app, equals: expectedJapanese)

        app.localization.changeLanguage(.english)
        app.applyPetAccessibility()

        expectAccessibility(of: app, equals: expectedEnglish)
    }

    // MARK: - Helpers

    private func expected(for language: AppLanguage) -> Expected {
        language == .japanese ? expectedJapanese : expectedEnglish
    }

    private func expectAccessibility(of app: AppDelegate, equals expected: Expected) {
        #expect(app.panel.accessibilityRole() == .window)
        #expect(app.panel.accessibilitySubrole() == .floatingWindow)
        #expect(app.panel.accessibilityTitle() == expected.windowTitle)
        #expect(app.petView.isAccessibilityElement())
        #expect(app.petView.accessibilityRole() == .image)
        #expect(app.petView.accessibilityLabel() == expected.petLabel)
        #expect(app.petView.accessibilityHelp() == expected.petHelp)
    }
}

/// A panel-only app with its own defaults suite, so the suite never reads or writes the developer's
/// real preferences.
@MainActor private final class IsolatedPetApp {
    let app: AppDelegate
    private let domain: String
    private let defaults: UserDefaults

    init(language: AppLanguage) throws {
        domain = "WaddlyTests.petAccessibility.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: domain))
        let settings = AppSettings(defaults: defaults)
        settings.registerDefaults()
        settings.appLanguage = language
        let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
        let localization = LocalizationController(settings: settings, resources: resources)
        app = AppDelegate(settings: settings, presenter: .invisible, localization: localization)
    }

    func close() {
        app.imageStore.beginShutdown()
        app.animationController.shutdown()
        app.panel.close()
        defaults.removePersistentDomain(forName: domain)
    }
}
