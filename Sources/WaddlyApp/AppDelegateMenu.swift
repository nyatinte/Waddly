import AppKit
import ServiceManagement
import WaddlyCore

private enum MenuBarIconRenderer {
    static func makeImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "waddly-menubar", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }

        image.size = NSSize(width: 24, height: 24)
        return image
    }
}

func copyMenuTree(_ menu: NSMenu) -> NSMenu {
    let copy = NSMenu(title: menu.title)
    for item in menu.items {
        if item.isSeparatorItem {
            copy.addItem(.separator())
            continue
        }
        let itemCopy = NSMenuItem(title: item.title, action: item.action, keyEquivalent: item.keyEquivalent)
        itemCopy.target = item.target
        itemCopy.tag = item.tag
        itemCopy.state = item.state
        itemCopy.isEnabled = item.isEnabled
        if let submenu = item.submenu {
            itemCopy.submenu = copyMenuTree(submenu)
        }
        copy.addItem(itemCopy)
    }
    return copy
}

func synchronizeMenuSelection(in menus: [NSMenu], action: Selector, selectedTag: Int) {
    func update(_ menu: NSMenu) {
        for item in menu.items {
            if item.action == action {
                item.state = item.tag == selectedTag ? .on : .off
            }
            if let submenu = item.submenu {
                update(submenu)
            }
        }
    }
    menus.forEach(update)
}

func updatePresenceMenuItems(dockItem: NSMenuItem, menuBarItem: NSMenuItem, showInDock: Bool, showInMenuBar: Bool) {
    dockItem.state = showInDock ? .on : .off
    menuBarItem.state = showInMenuBar ? .on : .off
    dockItem.isEnabled = showInMenuBar
    menuBarItem.isEnabled = showInDock
}

func pauseMenuTitleKey(isPaused: Bool) -> LocalizationKey {
    isPaused ? .menuResume : .menuPause
}

extension AppDelegate {
    private func makeSizeMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: localizedString(.menuDisplaySize), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let sizes: [(Int, LocalizationKey)] = [(180, .sizeSmall), (240, .sizeMedium), (320, .sizeLarge)]
        for (size, labelKey) in sizes {
            let title = "\(localizedString(labelKey)) (\(size) px)"
            let item = NSMenuItem(title: title, action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = size
            item.state = CGFloat(size) == displaySize ? .on : .off
            submenu.addItem(item)
        }
        menuItem.submenu = submenu
        return menuItem
    }

    func buildMenu() {
        statusMenu = NSMenu()
        statusMenu.delegate = self
        pauseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        loginItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        breathingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        dockVisibilityItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menuBarVisibilityItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        pauseItem.title = localizedString(pauseMenuTitleKey(isPaused: isPaused))
        pauseItem.action = #selector(togglePause)
        pauseItem.target = self
        statusMenu.addItem(pauseItem)
        statusMenu.addItem(.separator())

        statusMenu.addItem(makeSizeMenuItem())
        statusMenu.addItem(makeMotionMenuItem())
        addBreathingMenuItem()
        addLanguageMenu()
        statusMenu.addItem(.separator())
        addPresenceMenu()
        statusMenu.addItem(.separator())
        addWindowMenuItems()
        updatePresenceMenuState()

        statusItem.button?.image = makeStatusIcon()
        statusItem.button?.setAccessibilityLabel(localizedString(.a11yMenuBar))
        statusItem.menu = statusMenu
        petView.contextMenuProvider = { [weak self] in
            guard let self else { return nil }
            let menu = copyMenuTree(statusMenu)
            menu.delegate = self
            return menu
        }
        updateMenuStatus()
    }

    private func makeMotionMenuItem() -> NSMenuItem {
        let motionItem = NSMenuItem(title: localizedString(.menuTypingMotion), action: nil, keyEquivalent: "")
        let motionMenu = NSMenu()
        for motion in TypingMotion.allCases {
            let item = NSMenuItem(
                title: motion.title(using: localization),
                action: #selector(setTypingMotion(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = motion.rawValue
            item.state = motion == typingMotion ? .on : .off
            motionMenu.addItem(item)
        }
        motionItem.submenu = motionMenu
        return motionItem
    }

    private func addWindowMenuItems() {
        let imageSettingsItem = NSMenuItem(
            title: localizedString(.menuImageSettings),
            action: #selector(showImageSettings),
            keyEquivalent: ""
        )
        imageSettingsItem.target = self
        statusMenu.addItem(imageSettingsItem)

        let setupItem = NSMenuItem(
            title: localizedString(.menuSetupWizard),
            action: #selector(showSetupWizard),
            keyEquivalent: ""
        )
        setupItem.target = self
        statusMenu.addItem(setupItem)

        loginItem.title = localizedString(.menuLogin)
        loginItem.action = #selector(toggleLoginItem)
        loginItem.target = self
        statusMenu.addItem(loginItem)

        statusMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: localizedString(.menuQuit),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusMenu.addItem(quitItem)
    }

    private func addPresenceMenu() {
        let presenceItem = NSMenuItem(
            title: localizedString(.menuPresence),
            action: nil,
            keyEquivalent: ""
        )
        let presenceMenu = NSMenu()
        dockVisibilityItem.title = localizedString(.menuShowInDock)
        dockVisibilityItem.action = #selector(toggleDockVisibility)
        dockVisibilityItem.target = self
        menuBarVisibilityItem.title = localizedString(.menuShowInMenuBar)
        menuBarVisibilityItem.action = #selector(toggleMenuBarVisibility)
        menuBarVisibilityItem.target = self
        presenceMenu.addItem(dockVisibilityItem)
        presenceMenu.addItem(menuBarVisibilityItem)
        presenceItem.submenu = presenceMenu
        statusMenu.addItem(presenceItem)
    }

    private func addBreathingMenuItem() {
        breathingItem.title = localizedString(.menuBreathing)
        breathingItem.action = #selector(toggleBreathing)
        breathingItem.target = self
        breathingItem.state = isBreathingEnabled ? .on : .off
        statusMenu.addItem(breathingItem)
    }

    private func addLanguageMenu() {
        let languageItem = NSMenuItem(title: localizedString(.menuLanguage), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = NSMenuItem(
                title: localizedString(language.titleKey),
                action: #selector(setAppLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = language.rawValue
            item.state = language == localization.selectedLanguage ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        statusMenu.addItem(languageItem)
    }

    private func makeStatusIcon() -> NSImage? {
        MenuBarIconRenderer.makeImage()
    }

    func startMonitoring() {
        pauseItem.title = localizedString(isPaused ? .menuResume : .menuPause)
        guard hasCompletePetImageSet else {
            updateMenuStatus()
            return
        }
        if !isPaused {
            _ = monitor.start()
        }
        updateMenuStatus()
    }

    func updatePresenceOptions() {
        let showInDock = settings.showInDock
        let showInMenuBar = settings.showInMenuBar
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        statusItem.isVisible = showInMenuBar
        updatePresenceMenuState()
    }

    private func updatePresenceMenuState() {
        let showInDock = settings.showInDock
        let showInMenuBar = settings.showInMenuBar
        updatePresenceMenuItems(
            dockItem: dockVisibilityItem,
            menuBarItem: menuBarVisibilityItem,
            showInDock: showInDock,
            showInMenuBar: showInMenuBar
        )
    }

    @objc private func toggleDockVisibility() {
        settings.showInDock.toggle()
        updatePresenceOptions()
    }

    @objc private func toggleMenuBarVisibility() {
        settings.showInMenuBar.toggle()
        updatePresenceOptions()
    }

    private func updateMenuStatus() {
        pauseItem.title = localizedString(pauseMenuTitleKey(isPaused: isPaused))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let statusKey: LocalizationKey = isPaused
            ? .tooltipPaused
            : (monitor.isRunning ? .tooltipActive : .tooltipPermission)
        statusItem.button?.toolTip = localizedString(statusKey)
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        let size = CGFloat(sender.tag)
        settings.displaySize = size
        panel.setContentSize(NSSize(width: size, height: size))
        petView.frame = panel.contentView?.bounds ?? .zero
        panel.setFrameOrigin(clampedOrigin(panel.frame.origin))
        synchronizeMenuSelection(
            in: [statusMenu, sender.menu].compactMap(\.self),
            action: #selector(setSize(_:)),
            selectedTag: sender.tag
        )
        saveOrigin()
    }

    @objc private func setTypingMotion(_ sender: NSMenuItem) {
        guard let motion = TypingMotion(rawValue: sender.tag) else { return }
        settings.typingMotion = motion
        synchronizeMenuSelection(
            in: [statusMenu, sender.menu].compactMap(\.self),
            action: #selector(setTypingMotion(_:)),
            selectedTag: sender.tag
        )
        animationController.typingMotionDidChange(motion)
    }

    @objc private func toggleBreathing() {
        let enabled = !isBreathingEnabled
        settings.breathingEnabled = enabled
        breathingItem.state = enabled ? .on : .off
        animationController.breathingPreferenceDidChange()
    }

    @objc private func setAppLanguage(_ sender: NSMenuItem) {
        guard let language = AppLanguage(rawValue: sender.tag),
              language != localization.selectedLanguage else { return }
        localization.changeLanguage(language)
        pendingLocalizationRefresh = true
    }

    @objc private func togglePause() {
        let shouldPause = !animationController.isPaused
        animationController.setPaused(shouldPause)
        if shouldPause {
            monitor.stop()
        }
        startMonitoring()
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            pendingMenuError = true
        }
        updateMenuStatus()
    }

    func menuDidClose(_ menu: NSMenu) {
        if pendingLocalizationRefresh {
            pendingLocalizationRefresh = false
            buildMenu()
            petView.toolTip = localizedString(.petDropTooltip)
            setupWizardController?.refreshLocalization()
            refreshImageSettingsLocalization()
        }
        guard pendingMenuError else { return }
        pendingMenuError = false
        let alert = NSAlert()
        alert.messageText = localizedString(.menuLoginError)
        alert.alertStyle = .warning
        alert.beginSheetModal(for: panel)
    }
}
