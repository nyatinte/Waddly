import AppKit
import UniformTypeIdentifiers
import WaddlyCore

@MainActor
final class SetupWizardController: NSWindowController, NSWindowDelegate {
    /// Two setup steps, then a completion screen that hands the pet over to the desktop.
    enum Step: Int, CaseIterable {
        case pet
        case monitoring
        case completed

        static let visibleSteps: [Step] = [.pet, .monitoring]

        var titleKey: LocalizationKey {
            switch self {
            case .pet: .setupStepPet
            case .monitoring, .completed: .setupStepMonitoring
            }
        }
    }

    let localization: LocalizationController
    let promptResourcesURL: URL?
    let demoPetURL: URL?

    var prompt: String {
        SetupWizardController.loadPrompt(for: localization, resourcesAt: promptResourcesURL)
    }

    /// Reads a sheet without saving it, so the wizard can review it first.
    let onPreviewImage: @MainActor (URL) async -> PetImageSet?
    /// Commits the reviewed set.
    let onConfirmImage: @MainActor (PetImageSet) async -> Bool
    let currentPetImages: @MainActor () -> PetImageSet
    /// Owns the permission rules, the waiting, and the System Settings hand-off.
    let permission: PermissionService

    /// Records the step so a relaunch lands where the user left off. `nil` clears it.
    let onStepChange: @MainActor (Int?) -> Void
    let onShowOnDesktop: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    let stepIndicator = SetupStepIndicator(frame: .zero)
    let leftContainer = NSView()
    let previewPane = SetupPreviewPane(frame: .zero)
    let completionStage = NSView()
    let completionPetView = PixelImageView()
    lazy var completionPlayer = PetPreviewPlayer(imageView: completionPetView)
    let backButton = NSButton(title: "", target: nil, action: nil)
    let laterButton = NSButton(title: "", target: nil, action: nil)
    let nextButton = NSButton(title: "", target: nil, action: nil)

    var leftLeadingConstraint: NSLayoutConstraint?
    var leftCenterConstraint: NSLayoutConstraint?
    var leftWidthConstraint: NSLayoutConstraint?
    var previewWidthConstraint: NSLayoutConstraint?
    var previewHorizontalConstraints: [NSLayoutConstraint] = []
    private var lastRenderedStep: Step?
    var demoImages: PetImageSet?

    var currentStep = Step.pet
    var isShowingChatGPTGuide = false
    var didRegisterPet = false
    var importedFileName: String?
    var didFailCopy = false
    var didAttemptCopy = false
    var isShowingTroubleshooting = false

    init(
        localization: LocalizationController,
        promptResourcesURL: URL? = Bundle.main.resourceURL,
        demoPetURL: URL? = Bundle.main.url(forResource: "demo-pet", withExtension: "png"),
        onPreviewImage: @escaping @MainActor (URL) async -> PetImageSet?,
        onConfirmImage: @escaping @MainActor (PetImageSet) async -> Bool,
        currentPetImages: @escaping @MainActor () -> PetImageSet,
        permission: PermissionService,
        savedStep: Int? = nil,
        onStepChange: @escaping @MainActor (Int?) -> Void = { _ in },
        onShowOnDesktop: @escaping @MainActor () -> Void = {},
        onClose: @escaping @MainActor () -> Void
    ) {
        self.localization = localization
        self.promptResourcesURL = promptResourcesURL
        self.demoPetURL = demoPetURL
        self.onPreviewImage = onPreviewImage
        self.onConfirmImage = onConfirmImage
        self.currentPetImages = currentPetImages
        self.permission = permission
        self.onStepChange = onStepChange
        self.onShowOnDesktop = onShowOnDesktop
        self.onClose = onClose
        demoImages = SetupWizardController.loadDemoImages(from: demoPetURL)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SetupMetrics.contentSize),
            // The layout is designed for one fixed size; letting it stretch only distorted the columns.
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        if let savedStep, let restored = Step(rawValue: savedStep) {
            currentStep = restored
        }
        window.title = localizedString(.setupWindowTitle)
        window.contentMinSize = SetupMetrics.contentSize
        window.isReleasedWhenClosed = false
        // AppKit state restoration can hand back a frame that was resized in an earlier session,
        // which would break the fixed layout every state depends on.
        window.isRestorable = false
        window.delegate = self
        buildWindow()
    }

    required init?(coder: NSCoder) {
        nil
    }

    var hasImage: Bool {
        currentPetImages().isComplete
    }

    var isMonitoringGranted: Bool {
        permission.isGranted
    }

    /// True only when permission is granted and the keyboard is genuinely reaching Waddly.
    var isMonitoringReady: Bool {
        permission.isReady
    }

    /// The wizard itself is the drag guide, so it never hands off to a floating panel.
    var isShowingGuide: Bool {
        permission.isGuiding
    }

    var isShowingManualSteps: Bool {
        permission.isShowingManualSteps
    }

    func refreshPermissionStatus() {
        permission.refresh()
        guard currentStep != .pet else { return }
        renderCurrentStep()
    }

    func windowWillClose(_ notification: Notification) {
        permission.stop()
        window?.level = .normal
        previewPane.stopPlayback()
        completionPlayer.stop()
        onClose()
    }

    private static func loadDemoImages(from url: URL?) -> PetImageSet? {
        guard let url, let data = try? Data(contentsOf: url),
              let frames = PetSpriteSheetImporter.frames(from: data),
              frames.isComplete
        else { return nil }
        return frames
    }
}

extension SetupWizardController {
    func renderCurrentStep() {
        let page: NSView = switch currentStep {
        case .pet: makePetPage()
        case .monitoring: makeMonitoringPage()
        case .completed: makeCompletedPage()
        }
        leftContainer.subviews.forEach { $0.removeFromSuperview() }
        page.translatesAutoresizingMaskIntoConstraints = false
        leftContainer.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: leftContainer.trailingAnchor),
            page.topAnchor.constraint(equalTo: leftContainer.topAnchor),
            page.bottomAnchor.constraint(lessThanOrEqualTo: leftContainer.bottomAnchor)
        ])
        applyColumnLayout()
        updateHeader()
        updateFooter()
        updatePreview()
        fadeInPageIfStepChanged()
    }

    /// A short cross-fade between steps; skipped when the system asks for reduced motion.
    private func fadeInPageIfStepChanged() {
        let stepChanged = lastRenderedStep != currentStep
        let isFirstRender = lastRenderedStep == nil
        lastRenderedStep = currentStep
        guard stepChanged, !isFirstRender, !MotionPreference.isReduced else { return }
        leftContainer.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            leftContainer.animator().alphaValue = 1
        }
    }

    /// The completion screen is centred and compact instead of keeping the two-column split.
    private func applyColumnLayout() {
        let isCompact = currentStep == .completed
        previewPane.isHidden = isCompact
        leftLeadingConstraint?.isActive = !isCompact
        leftCenterConstraint?.isActive = isCompact
        // The pane keeps a fixed 330pt only while it is visible; the compact screen frees it.
        previewHorizontalConstraints.forEach { $0.isActive = !isCompact }
        leftWidthConstraint?.constant = isCompact ? 440 : SetupMetrics.leftColumnWidth
    }

    private func updateHeader() {
        stepIndicator.isHidden = currentStep == .completed
        guard currentStep != .completed else { return }
        stepIndicator.configure(
            titles: Step.visibleSteps.map { localizedString($0.titleKey) },
            currentIndex: currentStep.rawValue
        )
    }

    private func updateFooter() {
        backButton.title = localizedString(.setupBack)
        backButton.isHidden = currentStep == .pet
        switch currentStep {
        case .pet:
            nextButton.title = localizedString(.setupNext)
            nextButton.isEnabled = hasImage
            nextButton.isHidden = false
        case .monitoring:
            // While reactions are not working, the column owns the primary action and the footer only
            // offers the escape, so Next never competes with "Enable Input Monitoring".
            nextButton.isHidden = !isMonitoringReady
            nextButton.title = localizedString(.setupNext)
            nextButton.isEnabled = true
            laterButton.isHidden = isMonitoringReady
        case .completed:
            nextButton.isHidden = false
            nextButton.title = localizedString(.setupShowOnDesktop)
            nextButton.isEnabled = true
            laterButton.isHidden = true
        }
        if currentStep == .pet {
            laterButton.isHidden = true
        }
        window?.defaultButtonCell = nextButton.isHidden ? nil : nextButton.cell as? NSButtonCell
    }

    private func updatePreview() {
        guard currentStep != .completed else {
            updateCompletionPreview()
            return
        }
        if isShowingGuide {
            previewPane.showDropGuide()
            return
        }
        let images = currentPetImages()
        if images.isComplete {
            previewPane.showPet(images, caption: previewCaption, sleeping: shouldSleepInPreview)
        } else if let demoImages {
            previewPane.showDemo(demoImages, caption: localizedString(.setupDemoCaption))
        } else {
            previewPane.showPlaceholder(
                symbol: "pawprint",
                message: localizedString(.setupImageMissing),
                caption: ""
            )
        }
    }

    private func updateCompletionPreview() {
        let images = currentPetImages()
        if images.isComplete {
            completionPlayer.setImages(images)
            completionPlayer.playLoop()
        } else {
            completionPlayer.stop()
            completionPetView.image = images[.idle].first
        }
    }

    /// While reactions are missing, the pet sleeps on the permission step.
    private var shouldSleepInPreview: Bool {
        currentStep == .monitoring && !isMonitoringReady
    }

    /// The completion screen states the outcome, so the stage carries no repeated caption.
    private var previewCaption: String {
        guard currentStep == .monitoring else { return "" }
        // The ready page already says this in the column; only the failure state needs a caption.
        return isMonitoringReady ? "" : localizedString(.setupPreviewMonitoringOff)
    }
}
