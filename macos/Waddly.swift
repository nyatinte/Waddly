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

private enum PetImageCategory: String, CaseIterable {
    case idle
    case typing
    case sleep
    case enter

    var title: String { localizedString("images.category.\(rawValue)") }
}

private struct PetImageSet {
    private var images: [PetImageCategory: [NSImage]]

    init(_ images: [PetImageCategory: [NSImage]] = [:]) {
        self.images = images
    }

    subscript(_ category: PetImageCategory) -> [NSImage] {
        get { images[category] ?? [] }
        set { images[category] = newValue }
    }

    static func bundled(from images: [NSImage]) -> PetImageSet? {
        guard images.count == 16 else { return nil }
        return PetImageSet([
            .idle: [images[0], images[1]],
            .typing: [images[4], images[5], images[6], images[7], images[8], images[9], images[11]],
            .sleep: [images[12], images[13]],
            .enter: [images[10], images[14], images[15]]
        ])
    }
}

private struct OptimizedPetImage {
    let image: NSImage
    let pngData: Data
    let wasDownsampled: Bool
}

private enum PetSpriteSheetImporter {
    static let maximumFileSize = 20 * 1_024 * 1_024
    static let maximumImageDimension = 1_024

    static func optimizedImage(from data: Data) -> OptimizedPetImage? {
        guard data.count <= maximumFileSize,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              sourceType as String == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4_096, height <= 4_096,
              let cgImage = image(from: source, maxDimension: maximumImageDimension) else {
            return nil
        }

        guard hasAlpha(cgImage) else { return nil }
        let wasDownsampled = max(width, height) > maximumImageDimension
        guard let pngData = wasDownsampled ? pngData(from: cgImage) : data,
              pngData.count <= maximumFileSize else { return nil }
        return OptimizedPetImage(
            image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)),
            pngData: pngData,
            wasDownsampled: wasDownsampled
        )
    }

    static func image(from data: Data) -> NSImage? {
        optimizedImage(from: data)?.image
    }

    static func frames(from data: Data) -> PetImageSet? {
        guard data.count <= maximumFileSize,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              sourceType as String == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == height, width % 3 == 0, width <= 4_096,
              let image = image(from: source, maxDimension: maximumImageDimension * 3),
              hasAlpha(image) else {
            return nil
        }

        let cellSize = image.width / 3
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
        return PetImageSet([
            .idle: [cells[0], cells[1]],
            .typing: [cells[2], cells[3], cells[4], cells[5]],
            .sleep: [cells[7], cells[8]],
            .enter: [cells[6]]
        ])
    }

    static func load(from url: URL) -> NSImage? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= maximumFileSize,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let optimized = optimizedImage(from: data) else { return nil }
        if optimized.wasDownsampled { try? optimized.pngData.write(to: url, options: .atomic) }
        return optimized.image
    }

    static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            true
        default:
            false
        }
    }

    private static func image(from source: CGImageSource, maxDimension: Int) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        guard max(width, height) > maxDimension else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: false
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
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

@MainActor
private final class SpriteSheetGridOverlay: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let lines = NSBezierPath()
        lines.lineWidth = 1
        for division in 1...2 {
            let x = bounds.width * CGFloat(division) / 3
            let y = bounds.height * CGFloat(division) / 3
            lines.move(to: NSPoint(x: x, y: bounds.minY))
            lines.line(to: NSPoint(x: x, y: bounds.maxY))
            lines.move(to: NSPoint(x: bounds.minX, y: y))
            lines.line(to: NSPoint(x: bounds.maxX, y: y))
        }
        NSColor.separatorColor.withAlphaComponent(0.75).setStroke()
        lines.stroke()
    }
}

@MainActor
private final class PetImageDropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton ? hit : self
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []).filter { $0.pathExtension.lowercased() == "png" }
    }
}

@MainActor
private final class PetImageTileView: NSView {
    var onRemove: (() -> Void)?

    init(image: NSImage, index: Int, canRemove: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel("\(localizedString("images.thumbnail")) \(index + 1)")
        addSubview(imageView)

        let removeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)!, target: self, action: #selector(removeImage))
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.isBordered = false
        removeButton.isEnabled = canRemove
        removeButton.setAccessibilityLabel("\(localizedString("images.remove")) \(index + 1)")
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 88),
            heightAnchor.constraint(equalToConstant: 96),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 72),
            imageView.heightAnchor.constraint(equalToConstant: 72),
            removeButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            removeButton.widthAnchor.constraint(equalToConstant: 20),
            removeButton.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    required init?(coder: NSCoder) { nil }

    @objc private func removeImage() { onRemove?() }
}

@MainActor
private final class PetImageCategoryRowView: NSView {
    let category: PetImageCategory
    var onAdd: (() -> Void)?
    var onDrop: (([URL]) -> Void)? {
        didSet { dropView.onDrop = onDrop }
    }
    var onRemove: ((Int) -> Void)?

    private let dropView = PetImageDropView(frame: .zero)
    private let imageStack = NSStackView()

    init(category: PetImageCategory, images: [NSImage]) {
        self.category = category
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: category.title)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .boldSystemFont(ofSize: 13)
        title.setAccessibilityLabel(category.title)

        dropView.translatesAutoresizingMaskIntoConstraints = false
        dropView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder

        imageStack.orientation = .horizontal
        imageStack.alignment = .centerY
        imageStack.spacing = 8
        imageStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = imageStack
        dropView.addSubview(scrollView)

        let addButton = NSButton(title: localizedString("images.add"), target: self, action: #selector(addImages))
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.setAccessibilityLabel("\(localizedString("images.add")) — \(category.title)")
        addButton.translatesAutoresizingMaskIntoConstraints = false
        imageStack.addArrangedSubview(addButton)
        addButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true

        addSubview(title)
        addSubview(dropView)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 126),
            title.leadingAnchor.constraint(equalTo: leadingAnchor),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.widthAnchor.constraint(equalToConstant: 92),
            dropView.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 12),
            dropView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dropView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            dropView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            scrollView.leadingAnchor.constraint(equalTo: dropView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: dropView.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: dropView.topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: dropView.bottomAnchor, constant: -4),
            imageStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            imageStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            imageStack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            imageStack.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.widthAnchor),
            imageStack.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor)
        ])
        setImages(images)
    }

    required init?(coder: NSCoder) { nil }

    func setImages(_ images: [NSImage]) {
        for view in imageStack.arrangedSubviews where view is PetImageTileView {
            imageStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, image) in images.enumerated() {
            let tile = PetImageTileView(image: image, index: index, canRemove: images.count > 1)
            tile.onRemove = { [weak self] in self?.onRemove?(index) }
            imageStack.insertArrangedSubview(tile, at: index)
        }
    }

    @objc private func addImages() { onAdd?() }
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
    private lazy var bundledImages = (1...16).compactMap { index -> NSImage? in
        let name = String(format: "%02d", index)
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Frames/\(name)-\(Self.frameSlugs[index - 1]).png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
    private lazy var bundledImageSet: PetImageSet = {
        guard let imageSet = PetImageSet.bundled(from: bundledImages) else {
            fatalError("Waddly frame assets are incomplete")
        }
        return imageSet
    }()
    private var importedImages: PetImageSet?
    private var petImages: PetImageSet { importedImages ?? bundledImageSet }
    private var storedImageFiles: [String: [String]] = [:]
    private var panel: PetWindow!
    private var petView: DraggableImageView!
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var pauseItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var imageSettingsWindow: NSWindow?
    private var imageRows: [PetImageCategory: PetImageCategoryRowView] = [:]
    private var phaseTimer: Timer?
    private var idleBlinkTimer: Timer?
    private var sleepAnimationTimer: Timer?
    private var enterReactionTimer: Timer?
    private var enterReactionFrameIndex = 0
    private var lastInputTime = ProcessInfo.processInfo.systemUptime - 2.5
    private var lastTypingFrameTime: TimeInterval = 0
    private var typingFrameIndex = 0
    private var idleFrameIndex = 1
    private var sleepFrameIndex = 0
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
    private var petImagesDirectoryURL: URL? {
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
        sleepAnimationTimer?.invalidate()
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
        petView.image = petImages[.idle][0]
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

        let imageSettingsItem = NSMenuItem(title: localizedString("menu.imageSettings"), action: #selector(showImageSettings), keyEquivalent: "")
        imageSettingsItem.target = self
        statusMenu.addItem(imageSettingsItem)

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
        let legacyImages = customPetImageURL.flatMap { url -> PetImageSet? in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  size.intValue <= PetSpriteSheetImporter.maximumFileSize,
                  let data = try? Data(contentsOf: url) else { return nil }
            return PetSpriteSheetImporter.frames(from: data)
        }
        var loadedImages = legacyImages ?? bundledImageSet
        guard let directory = petImagesDirectoryURL else {
            importedImages = legacyImages
            return
        }

        let manifest = defaults.dictionary(forKey: "petImageFiles") as? [String: [String]] ?? [:]
        for category in PetImageCategory.allCases {
            let names = manifest[category.rawValue] ?? []
            var validNames: [String] = []
            let savedImages = names.compactMap { name -> NSImage? in
                guard name.hasSuffix(".png"), UUID(uuidString: String(name.dropLast(4))) != nil else { return nil }
                guard let image = PetSpriteSheetImporter.load(from: directory.appendingPathComponent(name)) else { return nil }
                validNames.append(name)
                return image
            }
            if !savedImages.isEmpty { loadedImages[category] = savedImages }
            storedImageFiles[category.rawValue] = validNames
        }
        if legacyImages != nil || !manifest.isEmpty { importedImages = loadedImages }
    }

    private func importPetImage(from url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= PetSpriteSheetImporter.maximumFileSize,
              let data = try? Data(contentsOf: url),
              let newImages = PetSpriteSheetImporter.frames(from: data) else {
            showPetImageImportError()
            return
        }
        guard confirmPetImageImport(data, cellSize: Int(newImages[.idle][0].size.width)) else { return }

        do {
            try persistPetImages(newImages)
        } catch {
            showImageSaveError()
            return
        }

        importedImages = newImages
        lastInputTime = ProcessInfo.processInfo.systemUptime - 2.5
        currentPhase = nil
        imageSetDidChange()
        schedulePhaseChange()
    }

    private func persistPetImages(_ imageSet: PetImageSet) throws {
        guard let directory = petImagesDirectoryURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let oldFiles = storedImageFiles
        var newFiles: [String: [String]] = [:]
        var createdURLs: [URL] = []
        do {
            for category in PetImageCategory.allCases {
                let images = imageSet[category]
                guard !images.isEmpty else { throw CocoaError(.validationMissingMandatoryProperty) }
                for image in images {
                    guard let data = PetSpriteSheetImporter.pngData(for: image),
                          data.count <= PetSpriteSheetImporter.maximumFileSize else { throw CocoaError(.fileWriteOutOfSpace) }
                    let name = "\(UUID().uuidString).png"
                    let url = directory.appendingPathComponent(name)
                    try data.write(to: url, options: .atomic)
                    createdURLs.append(url)
                    newFiles[category.rawValue, default: []].append(name)
                }
            }
        } catch {
            createdURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }

        defaults.set(newFiles, forKey: "petImageFiles")
        storedImageFiles = newFiles
        for names in oldFiles.values {
            for name in names where !newFiles.values.contains(where: { $0.contains(name) }) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    private func addImages(_ urls: [URL], to category: PetImageCategory) {
        var updated = petImages
        var addedCount = 0
        var skippedCount = 0
        var saveFailed = false
        for url in urls {
            guard url.pathExtension.lowercased() == "png",
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  size.intValue <= PetSpriteSheetImporter.maximumFileSize,
                  let data = try? Data(contentsOf: url),
                  let optimized = PetSpriteSheetImporter.optimizedImage(from: data) else {
                skippedCount += 1
                continue
            }
            do {
                try persistAddedImage(optimized.image, data: optimized.pngData, existingImages: updated[category], to: category)
                updated[category].append(optimized.image)
                importedImages = updated
                addedCount += 1
            } catch {
                saveFailed = true
                break
            }
        }
        guard addedCount > 0 else {
            showAlert("images.errorTitle", "images.errorMessage")
            return
        }
        imageSetDidChange()
        if saveFailed { showImageSaveError() }
        else if skippedCount > 0 { showAlert("images.skippedTitle", "images.skippedMessage") }
    }

    private func persistAddedImage(_ image: NSImage, data: Data, existingImages: [NSImage], to category: PetImageCategory) throws {
        guard let directory = petImagesDirectoryURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = category.rawValue
        let previousFiles = storedImageFiles[key] ?? []
        var names = previousFiles
        var createdURLs: [URL] = []
        do {
            if names.count != existingImages.count {
                names = []
                for existingImage in existingImages {
                    guard let imageData = PetSpriteSheetImporter.pngData(for: existingImage),
                          imageData.count <= PetSpriteSheetImporter.maximumFileSize else { throw CocoaError(.fileWriteOutOfSpace) }
                    let name = "\(UUID().uuidString).png"
                    let url = directory.appendingPathComponent(name)
                    try imageData.write(to: url, options: .atomic)
                    createdURLs.append(url)
                    names.append(name)
                }
            }
            let name = "\(UUID().uuidString).png"
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            createdURLs.append(url)
            names.append(name)
        } catch {
            createdURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }

        var updatedFiles = storedImageFiles
        updatedFiles[key] = names
        defaults.set(updatedFiles, forKey: "petImageFiles")
        storedImageFiles = updatedFiles
        for name in previousFiles where !names.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func removeImage(at index: Int, from category: PetImageCategory) {
        var updated = petImages
        guard updated[category].count > 1, updated[category].indices.contains(index) else { return }
        updated[category].remove(at: index)
        let key = category.rawValue
        let oldNames = storedImageFiles[key] ?? []
        if oldNames.count == petImages[category].count {
            var updatedFiles = storedImageFiles
            var newNames = oldNames
            let removedName = newNames.remove(at: index)
            updatedFiles[key] = newNames
            defaults.set(updatedFiles, forKey: "petImageFiles")
            storedImageFiles = updatedFiles
            if let directory = petImagesDirectoryURL {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(removedName))
            }
        } else {
            do {
                try persistPetImages(updated)
            } catch {
                showImageSaveError()
                return
            }
        }
        importedImages = updated
        imageSetDidChange()
    }

    private func imageSetDidChange() {
        stopEnterReaction()
        idleBlinkTimer?.invalidate()
        idleBlinkTimer = nil
        sleepAnimationTimer?.invalidate()
        sleepAnimationTimer = nil
        for category in PetImageCategory.allCases {
            imageRows[category]?.setImages(petImages[category])
        }
        switch currentPhase {
        case .typing:
            typingFrameIndex = 1
            show(petImages[.typing][0])
        case .idle:
            show(petImages[.idle][0])
            scheduleIdleBlink()
        case .sleeping:
            sleepFrameIndex = 0
            show(petImages[.sleep][0])
            scheduleSleepAnimation()
        case .frozen: show(petImages[.sleep].last!)
        case nil: break
        }
    }

    private func showPetImageImportError() {
        showAlert("pet.importErrorTitle", "pet.importErrorMessage")
    }

    private func showImageSaveError() {
        showAlert("images.saveErrorTitle", "images.saveErrorMessage")
    }

    private func showAlert(_ titleKey: String, _ messageKey: String) {
        let alert = NSAlert()
        alert.messageText = localizedString(titleKey)
        alert.informativeText = localizedString(messageKey)
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func confirmPetImageImport(_ data: Data, cellSize: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = localizedString("pet.previewTitle")
        alert.informativeText = localizedString("pet.previewPrompt")
        alert.alertStyle = .informational

        let previewSize: CGFloat = 240
        let detailsHeight: CGFloat = 72
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: previewSize, height: previewSize + detailsHeight))
        let imageView = NSImageView(frame: NSRect(x: 0, y: detailsHeight, width: previewSize, height: previewSize))
        imageView.image = NSImage(data: data)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.layer?.borderWidth = 1
        imageView.setAccessibilityLabel(localizedString("a11y.spritePreview"))

        let grid = SpriteSheetGridOverlay(frame: imageView.bounds)
        grid.autoresizingMask = [.width, .height]
        imageView.addSubview(grid)
        accessory.addSubview(imageView)

        let imageSize = cellSize * 3
        let details = [
            "\(localizedString("pet.previewImageSize")) \(imageSize) × \(imageSize) px",
            "\(localizedString("pet.previewCellSize")) \(cellSize) × \(cellSize) px",
            "\(localizedString("pet.previewDisplaySize")) \(Int(displaySize)) px",
            localizedString("pet.previewPosition")
        ].joined(separator: "\n")
        let detailsLabel = NSTextField(wrappingLabelWithString: details)
        detailsLabel.frame = NSRect(x: 0, y: 0, width: previewSize, height: detailsHeight)
        accessory.addSubview(detailsLabel)

        alert.accessoryView = accessory
        alert.addButton(withTitle: localizedString("pet.importConfirm"))
        alert.addButton(withTitle: localizedString("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func showImageSettings() {
        if imageSettingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = localizedString("images.windowTitle")
            window.minSize = NSSize(width: 620, height: 670)
            window.isReleasedWhenClosed = false

            let content = NSView()
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(stack)

            let note = NSTextField(wrappingLabelWithString: localizedString("images.instructions"))
            note.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(note)
            note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            for category in PetImageCategory.allCases {
                let row = PetImageCategoryRowView(category: category, images: petImages[category])
                row.onAdd = { [weak self] in self?.chooseImages(for: category) }
                row.onDrop = { [weak self] in self?.addImages($0, to: category) }
                row.onRemove = { [weak self] in self?.removeImage(at: $0, from: category) }
                imageRows[category] = row
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
            ])
            window.contentView = content
            imageSettingsWindow = window
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        imageSettingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func chooseImages(for category: PetImageCategory) {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.png]
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.prompt = localizedString("images.add")
        guard picker.runModal() == .OK else { return }
        addImages(picker.urls, to: category)
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
        let startsTyping = currentPhase != .typing
        let interruptedEnterReaction = enterReactionTimer != nil
        stopEnterReaction()
        sleepAnimationTimer?.invalidate()
        sleepAnimationTimer = nil
        lastInputTime = ProcessInfo.processInfo.systemUptime
        phaseTimer?.invalidate()
        idleBlinkTimer?.invalidate()
        idleBlinkTimer = nil
        petView.layer?.removeAnimation(forKey: "idle-breathe")
        petView.layer?.removeAnimation(forKey: "sleep-breathe")
        currentPhase = .typing

        if isEnter {
            playEnterReaction()
        } else if startsTyping {
            typingFrameIndex = 0
            show(petImages[.typing][typingFrameIndex])
            typingFrameIndex += 1
            lastTypingFrameTime = lastInputTime
            bounce()
        } else if interruptedEnterReaction || lastInputTime - lastTypingFrameTime >= 0.075 {
            show(petImages[.typing][typingFrameIndex % petImages[.typing].count])
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
                idleFrameIndex = 1
                show(petImages[.idle][0])
                breathe(key: "idle-breathe", breathScale: 1.01, duration: 3.2)
                scheduleIdleBlink()
            case .sleeping:
                idleBlinkTimer?.invalidate()
                idleBlinkTimer = nil
                petView.layer?.removeAllAnimations()
                sleepFrameIndex = 0
                show(petImages[.sleep][0])
                breathe()
                scheduleSleepAnimation()
            case .frozen:
                idleBlinkTimer?.invalidate()
                idleBlinkTimer = nil
                sleepAnimationTimer?.invalidate()
                sleepAnimationTimer = nil
                petView.layer?.removeAllAnimations()
                show(petImages[.sleep].last!)
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

    private func show(_ image: NSImage) {
        petView.image = image
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
        let sequence = petImages[.enter]
        enterReactionFrameIndex = 0
        show(sequence[enterReactionFrameIndex])
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

        enterReactionTimer = Timer.scheduledTimer(
            withTimeInterval: sequence.count > 1 ? 0.12 : 0.58,
            repeats: sequence.count > 1
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
                    self.show(self.petImages[.typing][0])
                    return
                }
                self.show(sequence[self.enterReactionFrameIndex])
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
        guard currentPhase == .idle, !isPaused, petImages[.idle].count > 1 else { return }
        idleBlinkTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 4...8), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.currentPhase == .idle, !self.isPaused else { return }
                let blinkImages = self.petImages[.idle]
                self.idleFrameIndex = Int.random(in: 1..<blinkImages.count)
                self.show(blinkImages[self.idleFrameIndex])
                self.idleBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.currentPhase == .idle, !self.isPaused else { return }
                        self.show(self.petImages[.idle][0])
                        self.scheduleIdleBlink()
                    }
                }
            }
        }
    }

    private func scheduleSleepAnimation() {
        sleepAnimationTimer?.invalidate()
        guard currentPhase == .sleeping, !isPaused, petImages[.sleep].count > 1 else { return }
        sleepAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.currentPhase == .sleeping, !self.isPaused else { return }
                let sleepImages = self.petImages[.sleep]
                self.sleepFrameIndex = (self.sleepFrameIndex + 1) % sleepImages.count
                self.show(sleepImages[self.sleepFrameIndex])
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
    }
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--self-test-sprite-sheet" {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])),
          let images = PetSpriteSheetImporter.frames(from: data),
          images[.idle].count == 2, images[.typing].count == 4,
          images[.sleep].count == 2, images[.enter].count == 1,
          PetSpriteSheetImporter.image(from: data) != nil else {
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
    guard PetSpriteSheetImporter.load(from: savedFile) != nil else {
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
    let bundled = PetImageSet.bundled(from: Array(repeating: NSImage(size: NSSize(width: 1, height: 1)), count: 16))
    precondition(bundled?[.idle].count == 2)
    precondition(bundled?[.typing].count == 7)
    precondition(bundled?[.sleep].count == 2)
    precondition(bundled?[.enter].count == 3)
    guard let context = CGContext(
        data: nil,
        width: 2_048,
        height: 2_048,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let largeImage = context.makeImage() else {
        fatalError("Image optimization test setup failed")
    }
    let sourceData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(sourceData, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Image optimization test setup failed")
    }
    CGImageDestinationAddImage(destination, largeImage, nil)
    guard CGImageDestinationFinalize(destination),
          let optimized = PetSpriteSheetImporter.optimizedImage(from: sourceData as Data),
          let optimizedSource = CGImageSourceCreateWithData(optimized.pngData as CFData, nil),
          let optimizedProperties = CGImageSourceCopyPropertiesAtIndex(optimizedSource, 0, nil) as? [CFString: Any],
          let optimizedWidth = optimizedProperties[kCGImagePropertyPixelWidth] as? Int,
          let optimizedHeight = optimizedProperties[kCGImagePropertyPixelHeight] as? Int,
          optimized.wasDownsampled,
          optimizedWidth == 1_024,
          optimizedHeight == 1_024,
          optimized.image.size.width == 1_024,
          optimized.image.size.height == 1_024 else {
        fatalError("Image downsampling failed")
    }
    print("Pet phases, image categories, and 1024px image optimization passed")
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
