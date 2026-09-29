import AppKit
import ApplicationServices
import QuartzCore
import ServiceManagement

private enum PetPhase: Equatable {
    case typing
    case idle
    case sleeping
    case frozen

    static func after(_ seconds: TimeInterval) -> PetPhase {
        let elapsed = max(0, seconds)
        if elapsed < 2.5 { return .typing }
        if elapsed < 25 { return .idle }
        if elapsed < 325 { return .sleeping }
        return .frozen
    }
}

@MainActor
private final class PetWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class DraggableImageView: NSImageView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class KeyboardMonitor: @unchecked Sendable {
    var onKeyDown: (@MainActor () -> Void)?
    private(set) var isRunning = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() -> Bool {
        guard !isRunning else { return true }
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        guard CGPreflightListenEventAccess() else { return false }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.handleEvent,
            userInfo: context
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        self.tap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
        isRunning = false
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .keyDown {
            MainActor.assumeIsolated {
                monitor.onKeyDown?()
            }
        } else if type == .tapDisabledByTimeout, let tap = monitor.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let defaults = UserDefaults.standard
    private let monitor = KeyboardMonitor()
    private lazy var frames = (1...16).compactMap { index -> NSImage? in
        let name = String(format: "%02d", index)
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Frames/\(name)-\(Self.frameSlugs[index - 1]).png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
    private let typingFrames = [5, 6, 5, 8, 7, 6, 9, 5, 11, 6, 8, 5]
    private var panel: PetWindow!
    private var petView: DraggableImageView!
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var permissionItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var visibilityItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var phaseTimer: Timer?
    private var idleBlinkTimer: Timer?
    private var lastInputTime = ProcessInfo.processInfo.systemUptime - 2.5
    private var lastTypingFrameTime: TimeInterval = 0
    private var typingFrameIndex = 0
    private var isPaused = false
    private var isVisible = true
    private var currentPhase: PetPhase?
    private var displaySize: CGFloat {
        let value = defaults.double(forKey: "displaySize")
        return value == 0 ? 240 : CGFloat(value)
    }

    private static let frameSlugs = [
        "idle", "blink", "surprised-left", "surprised-right",
        "laptop-look", "typing", "typing-fast", "peek-screen",
        "typing-excited", "focused", "jump", "one-hand-work",
        "sleepy", "sleep-sitting", "cheer", "picked-up"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        buildMenu()
        monitor.onKeyDown = { [weak self] in self?.receivedKeyDown() }
        startMonitoring()
        schedulePhaseChange()
    }

    func applicationWillTerminate(_ notification: Notification) {
        phaseTimer?.invalidate()
        idleBlinkTimer?.invalidate()
        monitor.stop()
    }

    func windowDidMove(_ notification: Notification) {
        saveOrigin()
    }

    private func buildPanel() {
        panel = PetWindow(
            contentRect: NSRect(x: 0, y: 0, width: displaySize, height: displaySize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.delegate = self

        petView = DraggableImageView(frame: panel.contentView?.bounds ?? .zero)
        petView.image = frames.first
        petView.imageScaling = .scaleProportionallyUpOrDown
        petView.wantsLayer = true
        petView.autoresizingMask = [.width, .height]
        panel.contentView = petView

        if let saved = defaults.array(forKey: "panelOrigin") as? [Double], saved.count == 2 {
            panel.setFrameOrigin(clampedOrigin(NSPoint(x: saved[0], y: saved[1])))
        } else {
            resetPosition()
        }
        panel.orderFrontRegardless()
    }

    private func buildMenu() {
        statusMenu = NSMenu()
        permissionItem = NSMenuItem(title: "入力監視を確認中…", action: #selector(openInputSettings), keyEquivalent: "")
        permissionItem.target = self
        statusMenu.addItem(permissionItem)

        pauseItem = NSMenuItem(title: "入力反応を一時停止", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        statusMenu.addItem(pauseItem)

        let sizeItem = NSMenuItem(title: "表示サイズ", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for size in [180, 240, 320] {
            let item = NSMenuItem(title: "\(size) px", action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = size
            item.state = CGFloat(size) == displaySize ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        statusMenu.addItem(sizeItem)

        let resetItem = NSMenuItem(title: "位置を右下に戻す", action: #selector(resetPosition), keyEquivalent: "")
        resetItem.target = self
        statusMenu.addItem(resetItem)

        visibilityItem = NSMenuItem(title: "ペンギンを隠す", action: #selector(toggleVisibility), keyEquivalent: "")
        visibilityItem.target = self
        statusMenu.addItem(visibilityItem)

        loginItem = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        statusMenu.addItem(loginItem)

        statusMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusMenu.addItem(quitItem)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Waddly")
        statusItem.menu = statusMenu
        updateMenuStatus()
    }

    private func startMonitoring() {
        if !isPaused && monitor.start() {
            permissionItem.title = "入力監視中（読み取りのみ）"
            permissionItem.action = nil
        } else if isPaused {
            permissionItem.title = "入力監視は一時停止中"
            permissionItem.action = nil
        } else {
            permissionItem.title = "入力監視の許可を再確認…"
            permissionItem.action = #selector(openInputSettings)
            permissionItem.target = self
        }
        pauseItem.title = isPaused ? "入力反応を再開" : "入力反応を一時停止"
        updateMenuStatus()
    }

    private func updateMenuStatus() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        statusItem.button?.toolTip = isPaused ? "ペンギン：一時停止中" : (monitor.isRunning ? "ペンギン：入力に反応中" : "ペンギン：入力監視の許可が必要")
    }

    private func receivedKeyDown() {
        guard !isPaused else { return }
        lastInputTime = ProcessInfo.processInfo.systemUptime
        phaseTimer?.invalidate()
        idleBlinkTimer?.invalidate()
        idleBlinkTimer = nil
        petView.layer?.removeAnimation(forKey: "idle-breathe")
        petView.layer?.removeAnimation(forKey: "sleep-breathe")
        currentPhase = .typing

        if lastInputTime - lastTypingFrameTime >= 0.075 {
            showFrame(typingFrames[typingFrameIndex % typingFrames.count])
            typingFrameIndex += 1
            lastTypingFrameTime = lastInputTime
            bounce()
        }
        schedulePhaseChange()
    }

    private func schedulePhaseChange() {
        phaseTimer?.invalidate()
        let elapsed = ProcessInfo.processInfo.systemUptime - lastInputTime
        let phase = PetPhase.after(elapsed)
        if phase != currentPhase {
            currentPhase = phase
            switch phase {
            case .typing:
                break
            case .idle:
                petView.layer?.removeAllAnimations()
                showFrame(0)
                breathe(key: "idle-breathe", breathScale: 1.01, duration: 3.2)
                scheduleIdleBlink()
            case .sleeping:
                idleBlinkTimer?.invalidate()
                idleBlinkTimer = nil
                petView.layer?.removeAllAnimations()
                showFrame(12)
                breathe()
            case .frozen:
                idleBlinkTimer?.invalidate()
                idleBlinkTimer = nil
                petView.layer?.removeAllAnimations()
                showFrame(12)
            }
        }

        let nextBoundary: TimeInterval?
        switch phase {
        case .typing: nextBoundary = 2.5
        case .idle: nextBoundary = 25
        case .sleeping: nextBoundary = 325
        case .frozen: nextBoundary = nil
        }
        guard let nextBoundary else { return }
        phaseTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, nextBoundary - elapsed), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePhaseChange() }
        }
    }

    private func showFrame(_ index: Int) {
        guard frames.indices.contains(index) else { return }
        petView.image = frames[index]
    }

    private func bounce() {
        guard let layer = petView.layer else { return }
        layer.removeAnimation(forKey: "type-bounce")
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = [0, 5, 0]
        animation.keyTimes = [0, 0.45, 1]
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "type-bounce")
    }

    private func breathe(key: String = "sleep-breathe", breathScale: CGFloat = 1.018, duration: CFTimeInterval = 1.5) {
        guard let layer = petView.layer else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1.0
        animation.toValue = breathScale
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key)
    }

    private func scheduleIdleBlink() {
        idleBlinkTimer?.invalidate()
        guard currentPhase == .idle, !isPaused else { return }
        idleBlinkTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 4...8), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.currentPhase == .idle, !self.isPaused else { return }
                self.showFrame(1)
                self.idleBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.currentPhase == .idle, !self.isPaused else { return }
                        self.showFrame(0)
                        self.scheduleIdleBlink()
                    }
                }
            }
        }
    }

    private func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        let frame = NSRect(origin: origin, size: panel.frame.size)
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return origin }
        let maxX = max(visible.minX, visible.maxX - frame.width)
        let maxY = max(visible.minY, visible.maxY - frame.height)
        return NSPoint(x: min(max(origin.x, visible.minX), maxX), y: min(max(origin.y, visible.minY), maxY))
    }

    private func saveOrigin() {
        let origin = panel.frame.origin
        defaults.set([origin.x, origin.y], forKey: "panelOrigin")
    }

    @objc private func resetPosition() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(x: visible.maxX - panel.frame.width - 18, y: visible.minY + 18)
        panel.setFrameOrigin(origin)
        saveOrigin()
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

    @objc private func togglePause() {
        isPaused.toggle()
        phaseTimer?.invalidate()
        if isPaused {
            monitor.stop()
            idleBlinkTimer?.invalidate()
            idleBlinkTimer = nil
            petView.layer?.removeAllAnimations()
        } else {
            lastInputTime = ProcessInfo.processInfo.systemUptime
            currentPhase = nil
        }
        startMonitoring()
        if !isPaused { schedulePhaseChange() }
    }

    @objc private func toggleVisibility() {
        isVisible.toggle()
        if isVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        visibilityItem.title = isVisible ? "ペンギンを隠す" : "ペンギンを表示する"
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            permissionItem.title = "ログイン時起動を設定できませんでした"
        }
        updateMenuStatus()
    }

    @objc private func openInputSettings() {
        if !isPaused && monitor.start() {
            startMonitoring()
            return
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
}

if CommandLine.arguments.contains("--self-test") {
    precondition(PetPhase.after(0) == .typing)
    precondition(PetPhase.after(2.5) == .idle)
    precondition(PetPhase.after(25) == .sleeping)
    precondition(PetPhase.after(325) == .frozen)
    print("Pet phase thresholds passed")
    exit(0)
}

@MainActor
private func runApplication() {
    let app = NSApplication.shared
    let appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.setActivationPolicy(.accessory)
    app.run()
}

runApplication()
