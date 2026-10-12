import AppKit
import QuartzCore
import WaddlyCore

extension PetImageSet {
    /// The nine cells in the order the sheet is read: idle ×2, typing ×4, Enter ×1, sleep ×2.
    var sheetOrderedFrames: [NSImage] {
        var frames: [NSImage] = []
        frames.append(contentsOf: self[.idle].prefix(2))
        frames.append(contentsOf: self[.typing].prefix(4))
        frames.append(contentsOf: self[.enter].prefix(1))
        frames.append(contentsOf: self[.sleep].prefix(2))
        return frames
    }
}

/// Right-hand column: the pet stage plus the controls that let the image be inspected before finishing.
@MainActor
final class SetupPreviewPane: PetImageDropView {
    private enum Mode: Int {
        case animation
        case cells
    }

    private static let animationOrder: [PetImageCategory] = [.idle, .typing, .enter, .sleep]

    let modeControl = NSSegmentedControl()
    let placeholderStack = NSStackView()
    let backgroundControl = NSSegmentedControl()
    private let stageLabel = NSTextField(labelWithString: "")
    private let petView = PixelImageView()
    private let gridView = SpriteSheetGridView(frame: .zero)
    let categoryRow = NSStackView()
    private let captionLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var player = PetPreviewPlayer(imageView: petView)

    var images = PetImageSet()
    var localization: LocalizationController?
    var showsControls = false
    var isSleeping = false
    /// While the drag guide is up, the stage is replaced by the "drag it here" illustration.
    var isShowingGuide = false
    let guideStack = NSStackView()
    var isGuideBuilt = false
    var guideLanguage: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = SetupMetrics.previewCornerRadius
        layer?.borderWidth = 1
        idleBorderColor = .separatorColor
        idleBorderWidth = 1
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        build()
        applyMode()
    }

    required init?(coder: NSCoder) {
        nil
    }

    var hasPet: Bool {
        images.isComplete
    }

    /// Whether the stage is animating. Closing setup stops it, so this is what tells a reopened
    /// screen apart from one that quietly gave up.
    var isPlayingPreview: Bool {
        player.isPlaying
    }

    func configure(localization: LocalizationController, showsControls: Bool) {
        self.localization = localization
        self.showsControls = showsControls
        modeControl.isHidden = !showsControls
        backgroundControl.isHidden = !showsControls
        categoryRow.isHidden = !showsControls
        rebuildControls()
        guideStack.isHidden = !isShowingGuide
    }

    /// Turns the stage into the drag guide: a mock of the settings list plus the draggable icon.
    func showDropGuide() {
        // Built on demand: before the first ask the guide must not exist, even hidden.
        if !isGuideBuilt || guideLanguage != localization?.activeLocalization {
            buildGuideIfNeeded()
        }
        isShowingGuide = true
        isSleeping = false
        player.stop()
        petView.isHidden = true
        gridView.isHidden = true
        placeholderStack.isHidden = true
        stageLabel.isHidden = true
        categoryRow.isHidden = true
        backgroundControl.isHidden = true
        // The preview controls are irrelevant while the stage is a drag instruction.
        modeControl.isHidden = true
        guideStack.isHidden = false
        captionLabel.stringValue = ""
    }

    private func endDropGuide() {
        guard isShowingGuide else { return }
        isShowingGuide = false
        guideStack.isHidden = true
        modeControl.isHidden = !showsControls
    }

    /// `sleeping` drives the permission step: the pet stays asleep until reactions are live.
    func showPet(_ images: PetImageSet, caption: String, sleeping: Bool = false) {
        endDropGuide()
        let framesChanged = !showsSameFrames(as: images, andCaption: caption)
        if framesChanged {
            self.images = images
            player.setImages(images)
            stageLabel.isHidden = true
            placeholderStack.isHidden = true
            petView.isHidden = false
            gridView.setFrames(images.sheetOrderedFrames)
        }
        captionLabel.stringValue = caption

        let poseChanged = isSleeping != sleeping
        isSleeping = sleeping
        if framesChanged || poseChanged {
            if sleeping {
                player.playSleeping()
            } else if poseChanged {
                // Waking up is an event: sleep → blink → typing, then the normal loop.
                player.playWakeUp()
            } else {
                player.playLoop()
            }
        }
        // A rerender can find the stage silent without anything having changed: closing the wizard
        // stops playback, and reopening it draws this same step again. `applyMode` starts a stopped
        // player and leaves a running one alone, so it has to run on every render.
        applyMode()
    }

    func showDemo(_ images: PetImageSet, caption: String) {
        endDropGuide()
        self.images = images
        player.setImages(images)
        isSleeping = false
        stageLabel.stringValue = localization?.string(for: .setupDemoLabel) ?? ""
        stageLabel.isHidden = false
        placeholderStack.isHidden = true
        petView.isHidden = false
        gridView.setFrames(images.sheetOrderedFrames)
        captionLabel.stringValue = caption
        player.playLoop()
        applyMode()
    }

    func showPlaceholder(symbol: String, message: String, caption: String) {
        endDropGuide()
        images = PetImageSet()
        player.stop()
        petView.image = nil
        petView.isHidden = true
        gridView.setFrames([])
        stageLabel.isHidden = true
        placeholderStack.isHidden = false
        setPlaceholderSymbol(symbol, message: message)
        captionLabel.stringValue = caption
        applyMode()
    }

    func celebrate() {
        guard hasPet, !MotionPreference.isReduced, let layer = petView.layer else { return }
        let hop = CAKeyframeAnimation(keyPath: "transform.scale")
        hop.values = [1, 1.12, 0.96, 1.04, 1]
        hop.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        hop.duration = 0.55
        hop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(hop, forKey: "setup-celebrate")
    }

    func stopPlayback() {
        player.stop()
    }

    // MARK: - Layout

    private func build() {
        configureControls()
        gridView.isHidden = true
        addSubview(modeControl)
        guideStack.orientation = .vertical
        guideStack.alignment = .centerX
        guideStack.spacing = 12
        guideStack.translatesAutoresizingMaskIntoConstraints = false
        guideStack.isHidden = true
        addSubview(placeholderStack)
        addSubview(guideStack)
        addSubview(backgroundControl)
        addSubview(stageLabel)
        addSubview(petView)
        addSubview(gridView)
        addSubview(categoryRow)
        addSubview(captionLabel)
        activatePaneLayout()
    }

    private func configureControls() {
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.target = self
        modeControl.action = #selector(changePreviewMode)

        backgroundControl.segmentCount = 2
        backgroundControl.trackingMode = .selectOne
        backgroundControl.selectedSegment = 0
        backgroundControl.translatesAutoresizingMaskIntoConstraints = false
        backgroundControl.target = self
        backgroundControl.action = #selector(changeBackground)

        stageLabel.font = .systemFont(ofSize: 11, weight: .medium)
        stageLabel.textColor = .tertiaryLabelColor
        stageLabel.translatesAutoresizingMaskIntoConstraints = false

        placeholderStack.orientation = .vertical
        placeholderStack.alignment = .centerX
        placeholderStack.spacing = 10
        placeholderStack.translatesAutoresizingMaskIntoConstraints = false
        placeholderStack.setAccessibilityElement(true)

        petView.translatesAutoresizingMaskIntoConstraints = false
        petView.imageScaling = .scaleProportionallyUpOrDown
        petView.wantsLayer = true

        categoryRow.orientation = .horizontal
        categoryRow.alignment = .centerY
        categoryRow.spacing = 6
        categoryRow.translatesAutoresizingMaskIntoConstraints = false

        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.alignment = .center
        captionLabel.font = .systemFont(ofSize: 12)
        captionLabel.textColor = .secondaryLabelColor
    }

    private func activatePaneLayout() {
        NSLayoutConstraint.activate([
            modeControl.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            modeControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            modeControl.widthAnchor.constraint(equalToConstant: 190),

            backgroundControl.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 10),
            backgroundControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            backgroundControl.widthAnchor.constraint(equalToConstant: 150),

            stageLabel.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 12),
            stageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            placeholderStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
            placeholderStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            placeholderStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            guideStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            guideStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4),
            guideStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            guideStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

            petView.centerXAnchor.constraint(equalTo: centerXAnchor),
            petView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
            petView.widthAnchor.constraint(equalToConstant: 200),
            petView.heightAnchor.constraint(equalToConstant: 200),

            gridView.centerXAnchor.constraint(equalTo: centerXAnchor),
            gridView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4),
            gridView.widthAnchor.constraint(equalToConstant: 240),
            gridView.heightAnchor.constraint(equalToConstant: 240),

            categoryRow.centerXAnchor.constraint(equalTo: centerXAnchor),
            categoryRow.topAnchor.constraint(equalTo: petView.bottomAnchor, constant: 10),

            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            captionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            captionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    private func showsSameFrames(as images: PetImageSet, andCaption caption: String) -> Bool {
        guard hasPet, captionLabel.stringValue == caption else { return false }
        return PetImageCategory.allCases.allSatisfy { category in
            let current = self.images[category]
            let incoming = images[category]
            return current.count == incoming.count
                && zip(current, incoming).allSatisfy { $0 === $1 }
        }
    }

    static let darkBackground = NSColor(calibratedWhite: 0.09, alpha: 1)
}

// MARK: - Preview controls

extension SetupPreviewPane {
    // MARK: - Controls

    @objc private func changePreviewMode() {
        applyMode()
    }

    @objc private func changeBackground() {
        gridView.setBackground(backgroundControl.selectedSegment == 1 ? Self.darkBackground : .white)
    }

    @objc private func playCategory(_ sender: NSButton) {
        guard Self.animationOrder.indices.contains(sender.tag) else { return }
        modeControl.selectedSegment = Mode.animation.rawValue
        applyMode()
        player.play(Self.animationOrder[sender.tag])
    }

    private func categoryTitle(for category: PetImageCategory) -> String {
        text(Self.localizedKey(for: category))
    }

    private static func localizedKey(for category: PetImageCategory) -> LocalizationKey {
        switch category {
        case .idle: .setupPreviewIdle
        case .typing: .setupPreviewTyping
        case .enter: .setupPreviewEnter
        case .sleep: .setupPreviewSleep
        }
    }

    private func applyMode() {
        let isCells = Mode(rawValue: modeControl.selectedSegment) == .cells
        let hasFrames = !images.sheetOrderedFrames.isEmpty
        petView.isHidden = isCells || !hasFrames
        gridView.isHidden = !isCells || !hasFrames
        categoryRow.isHidden = isCells || !showsControls || !hasFrames
        backgroundControl.isHidden = !isCells || !showsControls
        if isCells {
            player.stop()
        } else if hasFrames, !player.isPlaying {
            // Never restart playback that is already running; only fill a silent stage.
            if isSleeping {
                player.playSleeping()
            } else {
                player.playLoop()
            }
        }
    }

    private func rebuildControls() {
        applyControlLabels()
        rebuildCategoryButtons()
    }

    /// Localization is injected after `build()`, so missing text must never crash or leak optionals.
    private func text(_ key: LocalizationKey) -> String {
        guard let localization else { return "" }
        return localization.string(for: key)
    }

    private func applyControlLabels() {
        modeControl.segmentCount = 2
        modeControl.setLabel(text(.setupPreviewModeAnimation), forSegment: 0)
        modeControl.setLabel(text(.setupPreviewModeCells), forSegment: 1)
        modeControl.trackingMode = .selectOne
        modeControl.selectedSegment = Mode.animation.rawValue

        // These used to be set during build(), before localization was injected, so they stayed blank.
        backgroundControl.segmentCount = 2
        backgroundControl.setLabel(text(.setupPreviewLight), forSegment: 0)
        backgroundControl.setLabel(text(.setupPreviewDark), forSegment: 1)
        backgroundControl.setAccessibilityLabel(text(.setupPreviewBackground))
    }

    private func rebuildCategoryButtons() {
        for arrangedSubview in categoryRow.arrangedSubviews {
            categoryRow.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        for (index, category) in Self.animationOrder.enumerated() {
            let action = #selector(playCategory(_:))
            let button = NSButton(title: categoryTitle(for: category), target: self, action: action)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11)
            button.tag = index
            button.translatesAutoresizingMaskIntoConstraints = false
            categoryRow.addArrangedSubview(button)
        }
    }
}
