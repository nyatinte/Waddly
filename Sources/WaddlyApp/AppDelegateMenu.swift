import AppKit
import ServiceManagement
import WaddlyCore

private enum MenuBarIconRenderer {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            bodyPath().fill()
            faceDetailsPath().fill()
            beaniePath().fill()
            cuffPath().fill()
            pompomPath().fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func bodyPath() -> NSBezierPath {
        let penguin = NSBezierPath()
        penguin.windingRule = .evenOdd
        penguin.move(to: NSPoint(x: 9, y: 1))
        penguin.curve(
            to: NSPoint(x: 15.3, y: 7.8),
            controlPoint1: NSPoint(x: 12.8, y: 1),
            controlPoint2: NSPoint(x: 15.3, y: 4.1)
        )
        penguin.curve(
            to: NSPoint(x: 12.5, y: 12.2),
            controlPoint1: NSPoint(x: 15.3, y: 10),
            controlPoint2: NSPoint(x: 14.2, y: 11.6)
        )
        penguin.line(to: NSPoint(x: 11.9, y: 9.6))
        penguin.curve(
            to: NSPoint(x: 6.1, y: 9.6),
            controlPoint1: NSPoint(x: 10.3, y: 11.2),
            controlPoint2: NSPoint(x: 7.7, y: 11.2)
        )
        penguin.line(to: NSPoint(x: 5.5, y: 12.2))
        penguin.curve(
            to: NSPoint(x: 2.7, y: 7.8),
            controlPoint1: NSPoint(x: 3.8, y: 11.6),
            controlPoint2: NSPoint(x: 2.7, y: 10)
        )
        penguin.curve(
            to: NSPoint(x: 9, y: 1),
            controlPoint1: NSPoint(x: 2.7, y: 4.1),
            controlPoint2: NSPoint(x: 5.2, y: 1)
        )
        penguin.close()
        penguin.appendOval(in: NSRect(x: 5.2, y: 3.2, width: 7.6, height: 7.2))
        return penguin
    }

    private static func faceDetailsPath() -> NSBezierPath {
        let faceDetails = NSBezierPath()
        faceDetails.appendOval(in: NSRect(x: 6.8, y: 8.2, width: 0.9, height: 0.9))
        faceDetails.appendOval(in: NSRect(x: 10.3, y: 8.2, width: 0.9, height: 0.9))
        faceDetails.move(to: NSPoint(x: 8.2, y: 7.5))
        faceDetails.line(to: NSPoint(x: 9.8, y: 7.5))
        faceDetails.line(to: NSPoint(x: 9, y: 6.5))
        faceDetails.close()
        return faceDetails
    }

    private static func beaniePath() -> NSBezierPath {
        let hat = NSBezierPath()
        hat.move(to: NSPoint(x: 4.7, y: 11.2))
        hat.line(to: NSPoint(x: 4.7, y: 12.2))
        hat.curve(
            to: NSPoint(x: 6.1, y: 15),
            controlPoint1: NSPoint(x: 4.7, y: 13.7),
            controlPoint2: NSPoint(x: 5.1, y: 14.7)
        )
        hat.curve(
            to: NSPoint(x: 11.9, y: 15),
            controlPoint1: NSPoint(x: 7.2, y: 15.5),
            controlPoint2: NSPoint(x: 10.8, y: 15.5)
        )
        hat.curve(
            to: NSPoint(x: 13.3, y: 12.2),
            controlPoint1: NSPoint(x: 12.9, y: 14.7),
            controlPoint2: NSPoint(x: 13.3, y: 13.7)
        )
        hat.line(to: NSPoint(x: 13.3, y: 11.2))
        hat.close()
        return hat
    }

    private static func cuffPath() -> NSBezierPath {
        NSBezierPath(
            roundedRect: NSRect(x: 3.7, y: 10.6, width: 10.6, height: 1.9),
            xRadius: 0.8,
            yRadius: 0.8
        )
    }

    private static func pompomPath() -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: 7.8, y: 15.2, width: 2.4, height: 2.4))
    }
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
        pauseItem.title = localizedString(.menuPause)
        pauseItem.action = #selector(togglePause)
        pauseItem.target = self
        statusMenu.addItem(pauseItem)

        statusMenu.addItem(makeSizeMenuItem())

        let motionItem = NSMenuItem(title: localizedString(.menuTypingMotion), action: nil, keyEquivalent: "")
        let motionMenu = NSMenu()
        for motion in TypingMotion.allCases {
            let item = NSMenuItem(title: motion.title, action: #selector(setTypingMotion(_:)), keyEquivalent: "")
            item.target = self
            item.tag = motion.rawValue
            item.state = motion == typingMotion ? .on : .off
            motionMenu.addItem(item)
        }
        motionItem.submenu = motionMenu
        statusMenu.addItem(motionItem)

        addLanguageMenu()

        addBreathingMenuItem()

        addPresenceMenu()

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

        statusItem.button?.image = makeStatusIcon()
        statusItem.button?.setAccessibilityLabel(localizedString(.a11yMenuBar))
        statusItem.button?.title = " Waddly"
        statusItem.menu = statusMenu
        petView.contextMenu = statusMenu
        updateMenuStatus()
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
            item.state = language == AppLanguage.selected ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        statusMenu.addItem(languageItem)
    }

    private func makeStatusIcon() -> NSImage {
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
        dockVisibilityItem.state = showInDock ? .on : .off
        menuBarVisibilityItem.state = showInMenuBar ? .on : .off
        dockVisibilityItem.isEnabled = showInMenuBar
        menuBarVisibilityItem.isEnabled = showInDock
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
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
        saveOrigin()
    }

    @objc private func setTypingMotion(_ sender: NSMenuItem) {
        guard let motion = TypingMotion(rawValue: sender.tag) else { return }
        settings.typingMotion = motion
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
        animationController.typingMotionDidChange(motion)
    }

    @objc private func toggleBreathing() {
        let enabled = !isBreathingEnabled
        settings.breathingEnabled = enabled
        breathingItem.state = enabled ? .on : .off
        animationController.breathingPreferenceDidChange()
    }

    @objc private func setAppLanguage(_ sender: NSMenuItem) {
        guard let language = AppLanguage(rawValue: sender.tag), language != AppLanguage.selected else { return }
        settings.appLanguage = language
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }

        let alert = NSAlert()
        alert.messageText = localizedString(.languageRestartTitle)
        alert.informativeText = localizedString(.languageRestartMessage)
        alert.addButton(withTitle: localizedString(.languageRestartNow))
        alert.addButton(withTitle: localizedString(.languageRestartLater))
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    @objc private func togglePause() {
        let shouldPause = !animationController.isPaused
        animationController.setPaused(shouldPause)
        if shouldPause { monitor.stop() }
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
            let alert = NSAlert()
            alert.messageText = localizedString(.menuLoginError)
            alert.alertStyle = .warning
            alert.runModal()
        }
        updateMenuStatus()
    }
}
