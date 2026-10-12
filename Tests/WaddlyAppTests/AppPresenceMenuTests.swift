import AppKit
import Testing
@testable import WaddlyApp

/// The two presence switches, which are the only way back to the app once the other one is off.
struct AppPresenceMenuTests {
    /// Neither switch may be the one that leaves the app with no entry point. AppKit only listens to
    /// validation, and the pet's right-click menu is a copy of the status menu, so every surface has
    /// to answer the same way. An option that is already off stays available: that is how someone
    /// who somehow ended up with both off gets back.
    @Test(arguments: [
        (true, true, true, true),
        (true, false, false, true),
        (false, true, true, false),
        (false, false, true, true)
    ])
    @MainActor
    func rejectsTurningOffTheLastEntryPoint(
        showInDock: Bool,
        showInMenuBar: Bool,
        dockIsAvailable: Bool,
        menuBarIsAvailable: Bool
    ) throws {
        try withApp(showInDock: showInDock, showInMenuBar: showInMenuBar) { app in
            for menu in [app.statusMenu, copyMenuTree(app.statusMenu)] {
                let dock = try item("toggleDockVisibility", in: menu)
                let menuBar = try item("toggleMenuBarVisibility", in: menu)
                #expect(app.validateMenuItem(dock) == dockIsAvailable)
                #expect(app.validateMenuItem(menuBar) == menuBarIsAvailable)
                // The state `updatePresenceMenuItems` set has to agree with what validation answers,
                // or the menu would say one thing and do another.
                #expect(dock.isEnabled == app.validateMenuItem(dock))
                #expect(menuBar.isEnabled == app.validateMenuItem(menuBar))
            }
        }
    }

    /// The checkmarks follow the settings, so reopening the menu shows the current choice.
    @Test @MainActor func reflectsTheCurrentChoice() throws {
        try withApp(showInDock: true, showInMenuBar: false) { app in
            let dock = try item("toggleDockVisibility", in: app.statusMenu)
            let menuBar = try item("toggleMenuBarVisibility", in: app.statusMenu)
            #expect(dock.state == .on)
            #expect(menuBar.state == .off)
        }
    }

    /// The defaults are removed after the body runs, not while the app is still reading them.
    @MainActor
    private func withApp(
        showInDock: Bool,
        showInMenuBar: Bool,
        _ body: (AppDelegate) throws -> Void
    ) throws {
        _ = NSApplication.shared
        let name = "WaddlyTests.presence.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let app = AppDelegate(settings: AppSettings(defaults: defaults))
        app.settings.registerDefaults()
        app.buildMenu()
        app.settings.showInDock = showInDock
        app.settings.showInMenuBar = showInMenuBar
        app.updatePresenceOptions()
        try body(app)
    }

    @MainActor
    private func item(_ action: String, in menu: NSMenu) throws -> NSMenuItem {
        let items = menu.items.flatMap { [$0] + ($0.submenu?.items ?? []) }
        return try #require(items.first { $0.action == NSSelectorFromString(action) })
    }
}
