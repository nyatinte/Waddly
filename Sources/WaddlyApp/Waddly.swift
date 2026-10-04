import AppKit
import ApplicationServices
import ServiceManagement
import WaddlyCore

@MainActor
final class PetWindow: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
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
            url.pathExtension.lowercased() == "png"
        else {
            return nil
        }
        return url
    }
}

@MainActor
final class KeyboardMonitor {
    var onKeyDown: (@MainActor (Bool) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var permissionGranted: Bool {
        CGPreflightListenEventAccess()
    }

    var isRunning: Bool {
        tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    func requestPermission() -> Bool {
        if !permissionGranted {
            _ = CGRequestListenEventAccess()
        }
        return permissionGranted
    }

    nonisolated static func isEnterKeyCode(_ keyCode: Int64) -> Bool {
        keyCode == 36 || keyCode == 76
    }

    func start() -> Bool {
        guard requestPermission() else { return false }

        if let tap {
            if CGEvent.tapIsEnabled(tap: tap) {
                return true
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) {
                return true
            }
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

    // SwiftFormat orders access modifiers before nonisolated.
    // swiftlint:disable:next modifier_order
    private nonisolated static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        let isEnter = type == .keyDown && isEnterKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        // The source is installed only on the main run loop. Keep the C callback
        // bridge synchronous so stop() cannot race an outstanding actor hop.
        MainActor.assumeIsolated {
            if type == .keyDown {
                monitor.onKeyDown?(isEnter)
            } else if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let settings: AppSettings
    let monitor = KeyboardMonitor()
    var pendingImageUpdate: Task<Void, Never>?
    var isShuttingDown = false
    var imageLoadFailed = false
    var importedImages: PetImageSet?
    var imageThumbnails: [ObjectIdentifier: NSImage] = [:]
    var petImages: PetImageSet {
        importedImages ?? PetImageSet()
    }

    var hasCompletePetImageSet: Bool {
        petImages.isComplete
    }

    var storedImageFiles: [String: [String]] = [:]
    lazy var panel = PetWindow(
        contentRect: NSRect(x: 0, y: 0, width: displaySize, height: displaySize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    lazy var petView = DraggableImageView(frame: panel.contentView?.bounds ?? .zero)
    lazy var animationController = PetAnimationController(
        petView: petView,
        petImages: { [weak self] in self?.petImages ?? PetImageSet() },
        hasCompletePetImageSet: { [weak self] in self?.hasCompletePetImageSet ?? false },
        typingMotion: { [weak self] in self?.typingMotion ?? .weak },
        isBreathingEnabled: { [weak self] in self?.isBreathingEnabled ?? false }
    )
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var statusMenu = NSMenu()
    var pauseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var loginItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var breathingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var dockVisibilityItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var menuBarVisibilityItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var setupWizardController: SetupWizardController?
    var imageSettingsWindow: NSWindow?
    var imageRows: [PetImageCategory: PetImageCategoryRowView] = [:]
    var isPaused: Bool {
        animationController.isPaused
    }

    var typingMotion: TypingMotion {
        settings.typingMotion
    }

    var isBreathingEnabled: Bool {
        settings.breathingEnabled
    }

    var displaySize: CGFloat {
        settings.displaySize
    }

    var petImagesDirectoryURL = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first?.appendingPathComponent("Waddly", isDirectory: true)
        .appendingPathComponent("PetImages", isDirectory: true)

    init(settings: AppSettings = .standard) {
        self.settings = settings
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.registerDefaults()
        settings.ensurePresenceIsVisible()
        buildPanel()
        buildMenu()
        updatePresenceOptions()
        petView.onFileDrop = { [weak self] url in
            Task { _ = await self?.importPetImage(from: url) }
        }
        petView.acceptPNGFileDrops()
        petView.toolTip = localizedString(.petDropTooltip)
        monitor.onKeyDown = { [weak self] isEnter in self?.animationController.handleKeyDown(isEnter: isEnter) }
        Task {
            _ = await queueImageUpdate {
                await self.loadSavedPetImage()
                guard !self.isShuttingDown else { return false }
                self.imageSetDidChange(resetActivity: true)
                if self.hasCompletePetImageSet, self.settings.setupWizardSeen {
                    self.startMonitoring()
                    self.animationController.start()
                } else {
                    self.showSetupWizard()
                }
                return true
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        setupWizardController?.refreshPermissionStatus()
        guard hasCompletePetImageSet, !isPaused, monitor.permissionGranted else { return }
        startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        isShuttingDown = true
        animationController.shutdown()
        monitor.stop()
    }

    func windowDidMove(_ notification: Notification) {
        saveOrigin()
    }
}
