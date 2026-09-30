import AppKit
import ServiceManagement
import WaddlyCore

extension AppDelegate {
    private func makeSizeMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: localizedString("menu.displaySize"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (size, labelKey) in [(180, "size.small"), (240, "size.medium"), (320, "size.large")] {
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
        pauseItem.title = localizedString("menu.pause")
        pauseItem.action = #selector(togglePause)
        pauseItem.target = self
        statusMenu.addItem(pauseItem)

        statusMenu.addItem(makeSizeMenuItem())

        let motionItem = NSMenuItem(title: localizedString("menu.typingMotion"), action: nil, keyEquivalent: "")
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

        addBreathingMenuItem()

        addPresenceMenu()

        let imageSettingsItem = NSMenuItem(
            title: localizedString("menu.imageSettings"),
            action: #selector(showImageSettings),
            keyEquivalent: ""
        )
        imageSettingsItem.target = self
        statusMenu.addItem(imageSettingsItem)

        let setupItem = NSMenuItem(
            title: localizedString("menu.setupWizard"),
            action: #selector(showSetupWizard),
            keyEquivalent: ""
        )
        setupItem.target = self
        statusMenu.addItem(setupItem)

        loginItem.title = localizedString("menu.login")
        loginItem.action = #selector(toggleLoginItem)
        loginItem.target = self
        statusMenu.addItem(loginItem)

        statusMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: localizedString("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusMenu.addItem(quitItem)

        statusItem.button?.image = makeStatusIcon()
        statusItem.button?.setAccessibilityLabel(localizedString("a11y.menuBar"))
        statusItem.button?.title = " Waddly"
        statusItem.menu = statusMenu
        petView.contextMenu = statusMenu
        updateMenuStatus()
    }

    private func addPresenceMenu() {
        let presenceItem = NSMenuItem(
            title: localizedString("menu.presence"),
            action: nil,
            keyEquivalent: ""
        )
        let presenceMenu = NSMenu()
        dockVisibilityItem.title = localizedString("menu.showInDock")
        dockVisibilityItem.action = #selector(toggleDockVisibility)
        dockVisibilityItem.target = self
        menuBarVisibilityItem.title = localizedString("menu.showInMenuBar")
        menuBarVisibilityItem.action = #selector(toggleMenuBarVisibility)
        menuBarVisibilityItem.target = self
        presenceMenu.addItem(dockVisibilityItem)
        presenceMenu.addItem(menuBarVisibilityItem)
        presenceItem.submenu = presenceMenu
        statusMenu.addItem(presenceItem)
    }

    private func addBreathingMenuItem() {
        breathingItem.title = localizedString("menu.breathing")
        breathingItem.action = #selector(toggleBreathing)
        breathingItem.target = self
        breathingItem.state = isBreathingEnabled ? .on : .off
        statusMenu.addItem(breathingItem)
    }

    private func makeStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 2.2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 2, y: 14))
            path.line(to: NSPoint(x: 5.5, y: 4))
            path.line(to: NSPoint(x: 9, y: 10))
            path.line(to: NSPoint(x: 12.5, y: 4))
            path.line(to: NSPoint(x: 16, y: 14))
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    func startMonitoring() {
        pauseItem.title = localizedString(isPaused ? "menu.resume" : "menu.pause")
        guard hasCompletePetImageSet else {
            updateMenuStatus()
            return
        }
        if !isPaused { _ = monitor.start() }
        updateMenuStatus()
    }

    func updatePresenceOptions() {
        let showInDock = defaults.bool(forKey: "showInDock")
        let showInMenuBar = defaults.bool(forKey: "showInMenuBar")
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        statusItem.isVisible = showInMenuBar
        dockVisibilityItem.state = showInDock ? .on : .off
        menuBarVisibilityItem.state = showInMenuBar ? .on : .off
        dockVisibilityItem.isEnabled = showInMenuBar
        menuBarVisibilityItem.isEnabled = showInDock
    }

    @objc private func toggleDockVisibility() {
        defaults.set(!defaults.bool(forKey: "showInDock"), forKey: "showInDock")
        updatePresenceOptions()
    }

    @objc private func toggleMenuBarVisibility() {
        defaults.set(!defaults.bool(forKey: "showInMenuBar"), forKey: "showInMenuBar")
        updatePresenceOptions()
    }

    private func updateMenuStatus() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let statusKey = isPaused ? "tooltip.paused" : (monitor.isRunning ? "tooltip.active" : "tooltip.permission")
        statusItem.button?.toolTip = localizedString(statusKey)
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        let size = CGFloat(sender.tag)
        defaults.set(Double(size), forKey: "displaySize")
        panel.setContentSize(NSSize(width: size, height: size))
        petView.frame = panel.contentView?.bounds ?? .zero
        panel.setFrameOrigin(clampedOrigin(panel.frame.origin))
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
        saveOrigin()
    }

    @objc private func setTypingMotion(_ sender: NSMenuItem) {
        guard let motion = TypingMotion(rawValue: sender.tag) else { return }
        defaults.set(motion.rawValue, forKey: "typingMotion")
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
        if motion == .off {
            petView.layer?.removeAnimation(forKey: "type-bounce")
        }
    }

    @objc private func toggleBreathing() {
        let enabled = !isBreathingEnabled
        defaults.set(enabled, forKey: "breathingEnabled")
        breathingItem.state = enabled ? .on : .off
        petView.layer?.removeAnimation(forKey: "idle-breathe")
        petView.layer?.removeAnimation(forKey: "sleep-breathe")
        guard enabled, !isPaused else { return }
        switch currentPhase {
        case .idle: breathe(key: "idle-breathe", breathScale: 1.01, duration: 3.2)
        case .sleeping: breathe()
        case .typing, .frozen, nil: break
        }
    }

    @objc private func togglePause() {
        isPaused.toggle()
        phaseTimer?.invalidate()
        if isPaused {
            monitor.stop()
            idleBlinkTimer?.invalidate()
            idleBlinkTimer = nil
            sleepAnimationTimer?.invalidate()
            sleepAnimationTimer = nil
            stopEnterReaction()
            petView.layer?.removeAllAnimations()
        } else {
            lastInputTime = ProcessInfo.processInfo.systemUptime
            currentPhase = nil
            if hasCompletePetImageSet {
                show(petImages[.typing][0])
            }
        }
        startMonitoring()
        if !isPaused, hasCompletePetImageSet { schedulePhaseChange() }
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
            alert.messageText = localizedString("menu.loginError")
            alert.alertStyle = .warning
            alert.runModal()
        }
        updateMenuStatus()
    }}
