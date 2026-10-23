import AppKit
import Foundation
import Testing
@testable import WaddlyApp

/// The bar macOS users expect at the top of the screen: About (which is where the version lives),
/// Hide and Quit on the application menu, the editing commands text fields need, and Window.
@Suite(.serialized) @MainActor struct AppMainMenuTests {
    private func menus(language: AppLanguage = .english) throws -> AppMainMenu.Menus {
        let domain = "WaddlyTests.mainMenu.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = AppSettings(defaults: defaults)
        settings.appLanguage = language
        let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
        return AppMainMenu.build(
            localization: LocalizationController(settings: settings, resources: resources),
            appName: "Waddly"
        )
    }

    @Test func topLevelMenusAreTheApplicationEditAndWindowMenus() throws {
        let menus = try menus()
        #expect(menus.main.items.map(\.title) == ["Waddly", "Edit", "Window"])
        #expect(menus.main.items.allSatisfy { $0.submenu != nil })
        #expect(menus.main.item(at: 0)?.submenu?.item(at: 2)?.submenu === menus.services)
        #expect(menus.main.item(at: 2)?.submenu === menus.window)
    }

    @Test func aboutOpensTheStandardPanelThatReportsTheBundleVersion() throws {
        let appMenu = try #require(try menus().main.item(at: 0)?.submenu)
        let about = try #require(appMenu.item(at: 0))
        #expect(about.title == "About Waddly")
        #expect(about.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        #expect(about.target === NSApplication.shared)

        let quit = try #require(appMenu.items.last)
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
        #expect(quit.keyEquivalent == "q")
    }

    private struct ExpectedCommand {
        let title: String
        let key: String
        let action: Selector
    }

    @Test func editingCommandsKeepTheirSystemShortcuts() throws {
        let editMenu = try #require(try menus().main.item(at: 1)?.submenu)
        let expected = [
            ExpectedCommand(title: "Undo", key: "z", action: Selector(("undo:"))),
            ExpectedCommand(title: "Redo", key: "z", action: Selector(("redo:"))),
            ExpectedCommand(title: "Cut", key: "x", action: #selector(NSText.cut(_:))),
            ExpectedCommand(title: "Copy", key: "c", action: #selector(NSText.copy(_:))),
            ExpectedCommand(title: "Paste", key: "v", action: #selector(NSText.paste(_:))),
            ExpectedCommand(title: "Select All", key: "a", action: #selector(NSText.selectAll(_:)))
        ]
        let items = editMenu.items.filter { !$0.isSeparatorItem }
        #expect(items.map(\.title) == expected.map(\.title))
        for (item, command) in zip(items, expected) {
            #expect(item.keyEquivalent == command.key)
            #expect(item.action == command.action)
            #expect(item.target == nil) // The focused text field's field editor handles it.
        }
    }

    @Test func menuTitlesFollowTheSelectedLanguage() throws {
        let japanese = try menus(language: .japanese).main
        #expect(japanese.item(at: 0)?.title == "Waddly")
        #expect(japanese.item(at: 1)?.title == "編集")
        #expect(japanese.item(at: 2)?.title == "ウインドウ")
        #expect(try menus(language: .english).main.item(at: 1)?.title == "Edit")
    }
}
