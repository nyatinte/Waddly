import AppKit
import ApplicationServices
import ImageIO
import QuartzCore
import ServiceManagement
import UniformTypeIdentifiers

private func localizedString(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

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

private enum TypingMotion: Int, CaseIterable {
    case off
    case weak
    case strong

    var title: String {
        switch self {
        case .off: localizedString("motion.off")
        case .weak: localizedString("motion.weak")
        case .strong: localizedString("motion.strong")
        }
    }

    var amplitude: CGFloat {
        switch self {
        case .off: 0
        case .weak: 5
        case .strong: 10
        }
    }
}

private enum PetSpriteSheetImporter {
    static let maximumFileSize = 20 * 1_024 * 1_024
    static let cellForFrame = [0, 1, 2, 2, 2, 3, 5, 4, 5, 4, 6, 4, 7, 8, 6, 6]

    static func frames(from data: Data) -> [NSImage]? {
        guard data.count <= maximumFileSize,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              sourceType as String == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == height, width % 3 == 0, width <= 4_096,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            break
        default:
            return nil
        }

        let cellSize = width / 3
        let pointSize = CGFloat(cellSize)
        var cells: [NSImage] = []
        for row in 0..<3 {
            for column in 0..<3 {
                let rect = CGRect(
                    x: CGFloat(column * cellSize),
                    y: CGFloat(row * cellSize),
                    width: pointSize,
                    height: pointSize
                )
                guard let cell = image.cropping(to: rect) else { return nil }
                cells.append(NSImage(cgImage: cell, size: NSSize(width: pointSize, height: pointSize)))
            }
        }
        return cellForFrame.map { cells[$0] }
    }

    static func load(from url: URL) -> [NSImage]? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= maximumFileSize,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return frames(from: data)
    }

    static func save(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
private final class PetWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class DraggableImageView: NSImageView {
    var contextMenu: NSMenu?
    var onFileDrop: ((URL) -> Void)?

    func acceptPNGFileDrops() {
        registerForDraggedTypes([.fileURL])
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let contextMenu else { return }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURL(from: sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = fileURL(from: sender) else { return false }
        onFileDrop?(url)
        return true
    }

    private func fileURL(from sender: NSDraggingInfo) -> URL? {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
           let url = urls.first,
           url.pathExtension.lowercased() == "png" else {
            return nil
        }
        return url
    }
}

private final class KeyboardMonitor: @unchecked Sendable {
    var onKeyDown: (@MainActor (Bool) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var permissionGranted: Bool { CGPreflightListenEventAccess() }
    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    static func isEnterKeyCode(_ keyCode: Int64) -> Bool {
        keyCode == 36 || keyCode == 76
    }

    func start() -> Bool {
        if !permissionGranted {
            _ = CGRequestListenEventAccess()
        }
        guard permissionGranted else { return false }

        if let tap {
            if CGEvent.tapIsEnabled(tap: tap) { return true }
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) { return true }
            stop()
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.handleEvent,
            userInfo: context
        ) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        self.tap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard isRunning else {
            stop()
            return false
        }
        return isRunning
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
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .keyDown {
            let isEnter = isEnterKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            MainActor.assumeIsolated {
                monitor.onKeyDown?(isEnter)
            }
        } else if (type == .tapDisabledByTimeout || type == .tapDisabledByUserInput), let tap = monitor.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let defaults = UserDefaults.standard
    private let monitor = KeyboardMonitor()
    private lazy var bundledFrames = (1...16).compactMap { index -> NSImage? in
        let name = String(format: "%02d", index)
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Frames/\(name)-\(Self.frameSlugs[index - 1]).png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
    private var importedFrames: [NSImage]?
    private var frames: [NSImage] { importedFrames ?? bundledFrames }
    private let typingFrames = [5, 6, 5, 8, 7, 6, 9, 5, 11, 6, 8, 5]
    private var panel: PetWindow!
    private var petView: DraggableImageView!
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var pauseItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var phaseTimer: Timer?
    private var idleBlinkTimer: Timer?
    private var enterReactionTimer: Timer?
    private var enterReactionFrameIndex = 0
    private let enterReactionFrames = [10, 14, 15, 14, 10]
    private var lastInputTime = ProcessInfo.processInfo.systemUptime - 2.5
    private var lastTypingFrameTime: TimeInterval = 0
    private var typingFrameIndex = 0
    private var isPaused = false
    private var currentPhase: PetPhase?
    private var typingMotion: TypingMotion {
        TypingMotion(rawValue: defaults.integer(forKey: "typingMotion")) ?? .weak
    }
    private var displaySize: CGFloat {
        let value = defaults.double(forKey: "displaySize")
        return value == 0 ? 240 : CGFloat(value)
    }
    private var customPetImageURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Waddly", isDirectory: true)
            .appendingPathComponent("custom-pet.png")
    }

    private static let frameSlugs = [
        "idle", "blink", "surprised-left", "surprised-right",
        "laptop-look", "typing", "typing-fast", "peek-screen",
        "typing-excited", "focused", "jump", "one-hand-work",
        "sleepy", "sleep-sitting", "cheer", "picked-up"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["typingMotion": TypingMotion.weak.rawValue])
        loadSavedPetImage()
        buildPanel()
        buildMenu()
        petView.onFileDrop = { [weak self] in self?.importPetImage(from: $0) }
        petView.acceptPNGFileDrops()
        petView.toolTip = localizedString("pet.dropTooltip")
        monitor.onKeyDown = { [weak self] isEnter in self?.receivedKeyDown(isEnter: isEnter) }
        startMonitoring()
        schedulePhaseChange()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !isPaused, CGPreflightListenEventAccess() else { return }
        startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        phaseTimer?.invalidate()
        idleBlinkTimer?.invalidate()
        stopEnterReaction()
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
            placeAtDefaultPosition()
        }
        panel.orderFrontRegardless()
    }

    private func buildMenu() {
        statusMenu = NSMenu()

        pauseItem = NSMenuItem(title: localizedString("menu.pause"), action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        statusMenu.addItem(pauseItem)

        let sizeItem = NSMenuItem(title: localizedString("menu.displaySize"), action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (size, labelKey) in [(180, "size.small"), (240, "size.medium"), (320, "size.large")] {
            let title = "\(localizedString(labelKey)) (\(size) px)"
            let item = NSMenuItem(title: title, action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = size
            item.state = CGFloat(size) == displaySize ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        statusMenu.addItem(sizeItem)

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

        let importPetItem = NSMenuItem(title: localizedString("menu.importPet"), action: #selector(choosePetImage), keyEquivalent: "")
        importPetItem.target = self
        statusMenu.addItem(importPetItem)

        loginItem = NSMenuItem(title: localizedString("menu.login"), action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        statusMenu.addItem(loginItem)

        statusMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: localizedString("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusMenu.addItem(quitItem)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = makeStatusIcon()
        statusItem.button?.setAccessibilityLabel(localizedString("a11y.menuBar"))
        statusItem.button?.title = " Waddly"
        statusItem.menu = statusMenu
        petView.contextMenu = statusMenu
        updateMenuStatus()
    }

    private func loadSavedPetImage() {
        guard let url = customPetImageURL else { return }
        importedFrames = PetSpriteSheetImporter.load(from: url)
    }

    private func importPetImage(from url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= PetSpriteSheetImporter.maximumFileSize,
              let data = try? Data(contentsOf: url),
              let newFrames = PetSpriteSheetImporter.frames(from: data),
              let destination = customPetImageURL else {
            showPetImageImportError()
            return
        }

        do {
            try PetSpriteSheetImporter.save(data, to: destination)
        } catch {
            showPetImageImportError()
            return
        }

        stopEnterReaction()
        importedFrames = newFrames
        lastInputTime = ProcessInfo.processInfo.systemUptime - 2.5
        currentPhase = nil
        schedulePhaseChange()
    }

    private func showPetImageImportError() {
        let alert = NSAlert()
        alert.messageText = localizedString("pet.importErrorTitle")
        alert.informativeText = localizedString("pet.importErrorMessage")
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func choosePetImage() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.png]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.prompt = localizedString("pet.importPrompt")
        guard picker.runModal() == .OK, let url = picker.url else { return }
        importPetImage(from: url)
    }

    private func startMonitoring() {
        if !isPaused { _ = monitor.start() }
        pauseItem.title = localizedString(isPaused ? "menu.resume" : "menu.pause")
        updateMenuStatus()
    }

    private func updateMenuStatus() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let statusKey = isPaused ? "tooltip.paused" : (monitor.isRunning ? "tooltip.active" : "tooltip.permission")
        statusItem.button?.toolTip = localizedString(statusKey)
    }

    private func receivedKeyDown(isEnter: Bool) {
        guard !isPaused else { return }
        let interruptedEnterReaction = enterReactionTimer != nil
        stopEnterReaction()
        lastInputTime = ProcessInfo.processInfo.systemUptime
        phaseTimer?.invalidate()
        idleBlinkTimer?.invalidate()
        idleBlinkTimer = nil
        petView.layer?.removeAnimation(forKey: "idle-breathe")
        petView.layer?.removeAnimation(forKey: "sleep-breathe")
        currentPhase = .typing

        if isEnter {
            playEnterReaction()
        } else if interruptedEnterReaction || lastInputTime - lastTypingFrameTime >= 0.075 {
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
                showFrame(13)
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

    private func bounce() {
        let motion = typingMotion
        guard motion != .off else { return }
        guard let layer = petView.layer else { return }
        layer.removeAnimation(forKey: "type-bounce")
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = [0, motion.amplitude, 0]
        animation.keyTimes = [0, 0.45, 1]
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "type-bounce")
    }

    private func playEnterReaction() {
        let sequence = importedFrames == nil ? enterReactionFrames : [14]
        enterReactionFrameIndex = 0
        showFrame(sequence[enterReactionFrameIndex])
        enterReactionFrameIndex += 1

        if let layer = petView.layer {
            layer.removeAnimation(forKey: "type-bounce")
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1, 0.86, 1.12, 0.96, 1]
            scale.keyTimes = [0, 0.2, 0.48, 0.72, 1]
            scale.duration = 0.58

            let press = CAKeyframeAnimation(keyPath: "transform.translation.y")
            press.values = [0, 8, -5, 2, 0]
            press.keyTimes = scale.keyTimes
            press.duration = scale.duration

            let impact = CAAnimationGroup()
            impact.animations = [scale, press]
            impact.duration = scale.duration
            impact.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(impact, forKey: "enter-impact")
        }

        let isCustomPet = importedFrames != nil
        enterReactionTimer = Timer.scheduledTimer(
            withTimeInterval: isCustomPet ? 0.58 : 0.12,
            repeats: !isCustomPet
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.currentPhase == .typing, !self.isPaused else {
                    self.enterReactionTimer?.invalidate()
                    self.enterReactionTimer = nil
                    return
                }
                guard self.enterReactionFrameIndex < sequence.count else {
                    self.enterReactionTimer?.invalidate()
                    self.enterReactionTimer = nil
                    self.showFrame(0)
                    return
                }
                self.showFrame(sequence[self.enterReactionFrameIndex])
                self.enterReactionFrameIndex += 1
            }
        }
    }

    private func stopEnterReaction() {
        enterReactionTimer?.invalidate()
        enterReactionTimer = nil
        petView?.layer?.removeAnimation(forKey: "enter-impact")
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

    private func placeAtDefaultPosition() {
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
            petView.layer?.removeAllAnimations()
        } else {
            lastInputTime = ProcessInfo.processInfo.systemUptime
            currentPhase = nil
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
    }

}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--self-test-sprite-sheet" {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])),
          let frames = PetSpriteSheetImporter.frames(from: data), frames.count == 16 else {
        fatalError("3×3 transparent PNG import failed")
    }
    let savedFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("Waddly-self-test-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: savedFile) }
    do {
        try PetSpriteSheetImporter.save(data, to: savedFile)
    } catch {
        fatalError("3×3 PNG save failed: \(error)")
    }
    guard let restoredFrames = PetSpriteSheetImporter.load(from: savedFile), restoredFrames.count == 16 else {
        fatalError("3×3 PNG reload failed")
    }
    print("3×3 transparent PNG import and persistence passed")
    exit(0)
}

if CommandLine.arguments.contains("--self-test") {
    precondition(PetPhase.after(0) == .typing)
    precondition(PetPhase.after(2.5) == .idle)
    precondition(PetPhase.after(25) == .sleeping)
    precondition(PetPhase.after(325) == .frozen)
    precondition(TypingMotion.off.amplitude == 0)
    precondition(TypingMotion.weak.amplitude == 5)
    precondition(TypingMotion.strong.amplitude > TypingMotion.weak.amplitude)
    precondition(KeyboardMonitor.isEnterKeyCode(36))
    precondition(KeyboardMonitor.isEnterKeyCode(76))
    precondition(!KeyboardMonitor.isEnterKeyCode(0))
    precondition(PetSpriteSheetImporter.cellForFrame[10] == 6)
    precondition(PetSpriteSheetImporter.cellForFrame[12] == 7)
    precondition(PetSpriteSheetImporter.cellForFrame[13] == 8)
    precondition(PetSpriteSheetImporter.cellForFrame[14] == 6)
    print("Pet phases, typing motion, Enter detection, and sprite mapping passed")
    exit(0)
}

@MainActor
private func runApplication() {
    let app = NSApplication.shared
    let appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.setActivationPolicy(.regular)
    app.run()
}

runApplication()
