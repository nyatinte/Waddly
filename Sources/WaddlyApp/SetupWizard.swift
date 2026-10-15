import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WaddlyCore

@MainActor
final class SetupWizardController: NSWindowController, NSWindowDelegate, ObservableObject {
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

    let previewPane = SetupPreviewPane(frame: .zero)
    var demoImages: PetImageSet?

    @Published var currentStep = Step.pet
    @Published var isShowingChatGPTGuide = false
    @Published var didRegisterPet = false
    @Published var importedFileName: String?
    @Published var didFailCopy = false
    @Published var didAttemptCopy = false
    @Published var isShowingTroubleshooting = false

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

    /// The guide follows System Settings until the user moves it.
    private var following = GuideFollowing()
    private var wasShowingGuide = false
    private var isMovingProgrammatically = false

    var isFollowingSystemSettings: Bool {
        following.isActive
    }

    /// Re-enables following whenever the guide opens, and remembers the transition.
    func refreshGuideFollowing() {
        let guiding = isShowingGuide
        if guiding, !wasShowingGuide {
            following.begin()
        }
        wasShowingGuide = guiding
    }

    func recordProgrammaticGuideOrigin(_ origin: NSPoint) {
        following.recordProgrammaticMove(to: origin)
    }

    /// Runs an app-owned window move and records where it landed, so neither the move notification
    /// raised during the move nor a later one is mistaken for a user drag.
    func moveWindowProgrammatically(_ move: () -> Void) {
        isMovingProgrammatically = true
        move()
        isMovingProgrammatically = false
        if let window {
            following.recordProgrammaticMove(to: window.frame.origin)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isMovingProgrammatically, isShowingGuide, let window else { return }
        following.recordMove(to: window.frame.origin)
    }

    func windowWillClose(_ notification: Notification) {
        permission.stop()
        window?.level = .normal
        previewPane.stopPlayback()
        window?.contentView = nil
        window?.delegate = nil
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
        updatePreview()
        objectWillChange.send()
    }

    private func updatePreview() {
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
