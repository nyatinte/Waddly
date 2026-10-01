import AppKit
import WaddlyCore

@MainActor
final class SpriteSheetGridOverlay: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let lines = NSBezierPath()
        lines.lineWidth = 1
        for division in 1 ... 2 {
            let verticalPosition = bounds.width * CGFloat(division) / 3
            let horizontalPosition = bounds.height * CGFloat(division) / 3
            lines.move(to: NSPoint(x: verticalPosition, y: bounds.minY))
            lines.line(to: NSPoint(x: verticalPosition, y: bounds.maxY))
            lines.move(to: NSPoint(x: bounds.minX, y: horizontalPosition))
            lines.line(to: NSPoint(x: bounds.maxX, y: horizontalPosition))
        }
        NSColor.separatorColor.withAlphaComponent(0.75).setStroke()
        lines.stroke()
    }
}

@MainActor
final class PetImageDropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton ? hit : self
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(from: sender).isEmpty else { return [] }
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        restoreDropAppearance()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        restoreDropAppearance()
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func restoreDropAppearance() {
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
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
    var onMove: ((Int) -> Void)?
    private let index: Int

    init(image: NSImage, index: Int, imageCount: Int) {
        self.index = index
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel("\(localizedString(.imagesThumbnail)) \(index + 1)")
        addSubview(imageView)

        let removeButton = makeButton(title: "×", symbol: "xmark.circle.fill", action: #selector(removeImage))
        removeButton.isEnabled = imageCount > 1
        removeButton.setAccessibilityLabel("\(localizedString(.imagesRemove)) \(index + 1)")
        addSubview(removeButton)

        let moveLeftButton = makeButton(title: "‹", symbol: "chevron.left", action: #selector(moveImageLeft))
        moveLeftButton.isEnabled = index > 0
        moveLeftButton.setAccessibilityLabel("\(localizedString(.imagesMoveLeft)) \(index + 1)")
        addSubview(moveLeftButton)

        let moveRightButton = makeButton(title: "›", symbol: "chevron.right", action: #selector(moveImageRight))
        moveRightButton.isEnabled = index < imageCount - 1
        moveRightButton.setAccessibilityLabel("\(localizedString(.imagesMoveRight)) \(index + 1)")
        addSubview(moveRightButton)

        configureLayout(
            imageView: imageView,
            removeButton: removeButton,
            moveLeftButton: moveLeftButton,
            moveRightButton: moveRightButton
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func makeButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button.image = image
            button.imagePosition = .imageOnly
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        return button
    }

    private func configureLayout(
        imageView: NSImageView,
        removeButton: NSButton,
        moveLeftButton: NSButton,
        moveRightButton: NSButton
    ) {
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 88),
            heightAnchor.constraint(equalToConstant: 104),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            imageView.widthAnchor.constraint(equalToConstant: 64),
            imageView.heightAnchor.constraint(equalToConstant: 64),
            removeButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            removeButton.widthAnchor.constraint(equalToConstant: 20),
            removeButton.heightAnchor.constraint(equalToConstant: 20),
            moveLeftButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            moveLeftButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            moveLeftButton.widthAnchor.constraint(equalToConstant: 26),
            moveLeftButton.heightAnchor.constraint(equalToConstant: 20),
            moveRightButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            moveRightButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            moveRightButton.widthAnchor.constraint(equalToConstant: 26),
            moveRightButton.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    @objc private func removeImage() {
        onRemove?()
    }

    @objc private func moveImageLeft() {
        onMove?(index - 1)
    }

    @objc private func moveImageRight() {
        onMove?(index + 1)
    }
}

@MainActor
final class PetImageCategoryRowView: NSView {
    let category: PetImageCategory
    var onAdd: (() -> Void)?
    var onDrop: (([URL]) -> Void)? {
        didSet { dropView.onDrop = onDrop }
    }

    var onRemove: ((Int) -> Void)?
    var onMove: ((Int, Int) -> Void)?

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

        let addButton = NSButton(title: localizedString(.imagesAdd), target: self, action: #selector(addImages))
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.setAccessibilityLabel("\(localizedString(.imagesAdd)) — \(category.title)")
        addButton.translatesAutoresizingMaskIntoConstraints = false
        imageStack.addArrangedSubview(addButton)
        addButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true

        addSubview(title)
        addSubview(dropView)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 138),
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

    required init?(coder: NSCoder) {
        nil
    }

    func setImages(_ images: [NSImage]) {
        for view in imageStack.arrangedSubviews where view is PetImageTileView {
            imageStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, image) in images.enumerated() {
            let tile = PetImageTileView(image: image, index: index, imageCount: images.count)
            tile.onRemove = { [weak self] in self?.onRemove?(index) }
            tile.onMove = { [weak self] in self?.onMove?(index, $0) }
            imageStack.insertArrangedSubview(tile, at: index)
        }
    }

    @objc private func addImages() {
        onAdd?()
    }
}
