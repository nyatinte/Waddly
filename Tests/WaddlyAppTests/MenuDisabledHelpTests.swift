import AppKit
import Testing
@testable import WaddlyApp

@Suite(.serialized) @MainActor struct MenuDisabledHelpTests {
    @Test func imageAndSetupReasonsFollowTheCurrentStateInExistingMenus() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        let menus = [app.statusMenu, app.makePetContextMenu()]
        for menu in menus {
            menu.update()
            let character = try item("showChangeCharacter", in: menu)
            #expect(!character.isEnabled)
            #expect(character.toolTip == app.localizedString(.menuFinishSetupHelp))
        }
        let share = try item("showPetShare", in: menus[1])
        #expect(!share.isEnabled)
        #expect(share.toolTip == app.localizedString(.menuShareNeedsCharacter))

        try await app.persistPetImages(fixture.exampleImages())
        for menu in menus {
            menu.update()
            #expect(try !item("showChangeCharacter", in: menu).isEnabled)
        }
        #expect(share.isEnabled)
        #expect(share.toolTip == nil) // Sharing needs an image, not completed onboarding.
        if #available(macOS 14.4, *) {
            #expect(share.subtitle == nil)
        }

        app.settings.setupWizardSeen = true
        app.settings.setupStep = nil
        for menu in menus {
            menu.update()
            let character = try item("showChangeCharacter", in: menu)
            #expect(character.isEnabled)
            #expect(character.toolTip == nil)
        }
        app.settings.setupStep = SetupWizardController.Step.monitoring.rawValue
        for menu in menus {
            menu.update()
            let character = try item("showChangeCharacter", in: menu)
            #expect(!character.isEnabled)
            #expect(character.toolTip == app.localizedString(.menuFinishSetupHelp))
        }
    }

    @Test func presenceReasonsRefreshInExistingStatusAndContextSubmenus() throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        let menus = [app.statusMenu, app.makePetContextMenu()]
        for (dock, bar) in [(true, false), (false, true), (true, true), (false, false)] {
            app.settings.showInDock = dock
            app.settings.showInMenuBar = bar
            for menu in menus {
                let dockItem = try item("toggleDockVisibility", in: menu)
                let barItem = try item("toggleMenuBarVisibility", in: menu)
                try #require(dockItem.menu).update()
                #expect(dockItem.isEnabled == (bar || !dock))
                #expect(barItem.isEnabled == (dock || !bar))
                let reason = app.localizedString(.menuKeepEntryPointHelp)
                #expect(dockItem.toolTip == (dockItem.isEnabled ? nil : reason))
                #expect(barItem.toolTip == (barItem.isEnabled ? nil : reason))
                if #available(macOS 14.4, *) {
                    #expect(dockItem.subtitle == dockItem.toolTip)
                    #expect(barItem.subtitle == barItem.toolTip)
                }
            }
        }
    }

    @Test(arguments: [AppLanguage.japanese, .english])
    func helpCopyResolvesInBothLanguageResources(language: AppLanguage) throws {
        let domain = "WaddlyTests.menuHelp.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = AppSettings(defaults: defaults)
        settings.appLanguage = language
        let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
        let localization = LocalizationController(settings: settings, resources: resources)
        let expected: [String] = language == .japanese ? [
            "変更するにはセットアップを完了してください。",
            "Dockとメニューバーは両方とも隠せません。",
            "先にキャラクターを登録してください。"
        ] : [
            "Finish setup to change character.",
            "Keep Dock or Menu Bar enabled.",
            "Add a character before sharing."
        ]
        let keys: [LocalizationKey] = [.menuFinishSetupHelp, .menuKeepEntryPointHelp, .menuShareNeedsCharacter]
        #expect(keys.map { localization.string(for: $0) } == expected)
    }

    private func item(_ action: String, in menu: NSMenu) throws -> NSMenuItem {
        let items = menu.items.flatMap { [$0] + ($0.submenu?.items ?? []) }
        let item = try #require(items.first { $0.action == NSSelectorFromString(action) })
        if #available(macOS 14.4, *) {
            #expect(item.subtitle == item.toolTip)
        }
        return item
    }
}
