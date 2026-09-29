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
        if !isPaused { _ = monitor.start() }
        pauseItem.title = localizedString(isPaused ? "menu.resume" : "menu.pause")
        updateMenuStatus()
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
            show(petImages[.typing][0])
        }
        startMonitoring()
        if !isPaused { schedulePhaseChange() }
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
