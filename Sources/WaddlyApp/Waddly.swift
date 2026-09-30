import AppKit
import ApplicationServices
import ServiceManagement
import WaddlyCore

@MainActor
final class PetWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DraggableImageView: NSImageView {
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

final class KeyboardMonitor: @unchecked Sendable {
    var onKeyDown: (@MainActor (Bool) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var permissionGranted: Bool { CGPreflightListenEventAccess() }
    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func requestPermission() -> Bool {
        if !permissionGranted {
            _ = CGRequestListenEventAccess()
        }
        return permissionGranted
    }

    static func isEnterKeyCode(_ keyCode: Int64) -> Bool {
        keyCode == 36 || keyCode == 76
    }

    func start() -> Bool {
        guard requestPermission() else { return false }

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
        } else if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let tap = monitor.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let defaults = UserDefaults.standard
    let monitor = KeyboardMonitor()
    lazy var bundledImages = (1...16).compactMap { index -> NSImage? in
        let name = String(format: "%02d", index)
        let frameName = "\(name)-\(Self.frameSlugs[index - 1]).png"
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }
        return NSImage(contentsOf: resourceURL.appendingPathComponent("Frames/\(frameName)"))
    }
    lazy var bundledImageSet: PetImageSet = {
        guard let imageSet = PetImageSet.bundled(from: bundledImages) else {
            fatalError("Waddly frame assets are incomplete")
        }
        return imageSet
    }()
    var importedImages: PetImageSet?
    var petImages: PetImageSet { importedImages ?? bundledImageSet }
    var storedImageFiles: [String: [String]] = [:]
    lazy var panel = PetWindow(
        contentRect: NSRect(x: 0, y: 0, width: displaySize, height: displaySize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    lazy var petView = DraggableImageView(frame: panel.contentView?.bounds ?? .zero)
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var statusMenu = NSMenu()
    var pauseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var loginItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var dockVisibilityItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var menuBarVisibilityItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var setupWizardController: SetupWizardController?
    var imageSettingsWindow: NSWindow?
    var imageRows: [PetImageCategory: PetImageCategoryRowView] = [:]
    var phaseTimer: Timer?
    var idleBlinkTimer: Timer?
    var sleepAnimationTimer: Timer?
    var enterReactionTimer: Timer?
    var enterReactionFrameIndex = 0
    var lastInputTime = ProcessInfo.processInfo.systemUptime - 2.5
    var lastTypingFrameTime: TimeInterval = 0
    var typingFrameIndex = 0
    var idleFrameIndex = 1
    var sleepFrameIndex = 0
    var isPaused = false
    var currentPhase: PetPhase?
    var typingMotion: TypingMotion {
        TypingMotion(rawValue: defaults.integer(forKey: "typingMotion")) ?? .weak
    }
    var displaySize: CGFloat {
        let value = defaults.double(forKey: "displaySize")
        return value == 0 ? 240 : CGFloat(value)
    }
    var customPetImageURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Waddly", isDirectory: true)
            .appendingPathComponent("custom-pet.png")
    }
    var petImagesDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Waddly", isDirectory: true)
            .appendingPathComponent("PetImages", isDirectory: true)
    }
    private static let frameSlugs = [
        "idle", "blink", "surprised-left", "surprised-right",
        "laptop-look", "typing", "typing-fast", "peek-screen",
        "typing-excited", "focused", "jump", "one-hand-work",
        "sleepy", "sleep-sitting", "cheer", "picked-up"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [
            "typingMotion": TypingMotion.weak.rawValue,
            "showInDock": true,
            "showInMenuBar": true
        ])
        if !defaults.bool(forKey: "showInDock"), !defaults.bool(forKey: "showInMenuBar") {
            defaults.set(true, forKey: "showInDock")
        }
        loadSavedPetImage()
        buildPanel()
        buildMenu()
        updatePresenceOptions()
        petView.onFileDrop = { [weak self] in _ = self?.importPetImage(from: $0) }
        petView.acceptPNGFileDrops()
        petView.toolTip = localizedString("pet.dropTooltip")
        monitor.onKeyDown = { [weak self] isEnter in self?.receivedKeyDown(isEnter: isEnter) }
        if defaults.bool(forKey: "setupWizardSeen") {
            startMonitoring()
        } else {
            showSetupWizard()
        }
        schedulePhaseChange()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        setupWizardController?.refreshPermissionStatus()
        guard !isPaused, monitor.permissionGranted else { return }
        startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        phaseTimer?.invalidate()
        idleBlinkTimer?.invalidate()
        sleepAnimationTimer?.invalidate()
        stopEnterReaction()
        monitor.stop()
    }

    func windowDidMove(_ notification: Notification) {
        saveOrigin()
    }
}
