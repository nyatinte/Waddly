import AppKit

/// The menu bar at the top of the screen, holding what macOS users expect to find there.
///
/// Waddly's own commands live in the status item menu and in the pet's context menu, so this bar only
/// carries the standard commands: About (which reports the bundle version), Services, Hide, Quit,
/// Edit — so ⌘C and ⌘V reach text fields — and Window. Every item is the plain system action, so
/// AppKit's responder chain and automatic enabling decide when each one applies.
@MainActor
enum AppMainMenu {
    /// The submenus `NSApplication` has to be told about separately from the bar itself.
    struct Menus {
        let main: NSMenu
        let services: NSMenu
        let window: NSMenu
    }

    static var applicationName: String {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
              !name.isEmpty
        else {
            return "Waddly"
        }
        return name
    }

    static func build(
        localization: LocalizationController,
        appName: String = applicationName
    ) -> Menus {
        let services = NSMenu(title: localization.string(for: .mainMenuServices))
        let window = makeWindowMenu(localization: localization)
        let main = NSMenu(title: appName)
        main.addItem(wrapping: makeAppMenu(localization: localization, appName: appName, services: services))
        main.addItem(wrapping: makeEditMenu(localization: localization))
        main.addItem(wrapping: window)
        return Menus(main: main, services: services, window: window)
    }

    private static func makeAppMenu(
        localization: LocalizationController,
        appName: String,
        services: NSMenu
    ) -> NSMenu {
        let menu = NSMenu(title: appName)
        let about = item(
            localization.string(for: .mainMenuAbout),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            target: NSApplication.shared
        )
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(wrapping: services)
        menu.addItem(.separator())

        let app = NSApplication.shared
        menu.addItem(item(
            localization.string(for: .mainMenuHide),
            action: #selector(NSApplication.hide(_:)),
            key: "h",
            target: app
        ))
        menu.addItem(item(
            localization.string(for: .mainMenuHideOthers),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            key: "h",
            modifiers: [.command, .option],
            target: app
        ))
        menu.addItem(item(
            localization.string(for: .mainMenuShowAll),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            target: app
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            localization.string(for: .mainMenuQuit),
            action: #selector(NSApplication.terminate(_:)),
            key: "q",
            target: app
        ))
        return menu
    }

    /// Editing commands go to the first responder, so the field editor of whatever text field is
    /// focused handles them and AppKit disables them when nothing is editable.
    private static func makeEditMenu(localization: LocalizationController) -> NSMenu {
        let menu = NSMenu(title: localization.string(for: .mainMenuEdit))
        // Undo and Redo are the field editor's own actions, which are declared by the selector name
        // `undo:` / `redo:` rather than by a Swift method to point `#selector` at.
        menu.addItem(item(localization.string(for: .mainMenuUndo), action: Selector(("undo:")), key: "z"))
        menu.addItem(item(
            localization.string(for: .mainMenuRedo),
            action: Selector(("redo:")),
            key: "z",
            modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(item(localization.string(for: .mainMenuCut), action: #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item(localization.string(for: .mainMenuCopy), action: #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item(localization.string(for: .mainMenuPaste), action: #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item(
            localization.string(for: .mainMenuSelectAll),
            action: #selector(NSText.selectAll(_:)),
            key: "a"
        ))
        return menu
    }

    /// Window management plus the open windows. AppKit fills in the window list and the system's own
    /// window commands, which is why this menu defines only the parts it owns.
    private static func makeWindowMenu(localization: LocalizationController) -> NSMenu {
        let menu = NSMenu(title: localization.string(for: .mainMenuWindow))
        menu.addItem(item(
            localization.string(for: .mainMenuMinimize),
            action: #selector(NSWindow.performMiniaturize(_:)),
            key: "m"
        ))
        menu.addItem(item(localization.string(for: .mainMenuZoom), action: #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item(
            localization.string(for: .mainMenuBringAllToFront),
            action: #selector(NSApplication.arrangeInFront(_:)),
            target: NSApplication.shared
        ))
        return menu
    }

    private static func item(
        _ title: String,
        action: Selector?,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}

private extension NSMenu {
    func addItem(wrapping submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}

extension AppDelegate {
    /// Installs the standard menu bar. It is rebuilt with the status menu so a language change
    /// reaches both surfaces.
    func installMainMenu() {
        let menus = AppMainMenu.build(localization: localization)
        NSApp.mainMenu = menus.main
        NSApp.servicesMenu = menus.services
        NSApp.windowsMenu = menus.window
    }
}
