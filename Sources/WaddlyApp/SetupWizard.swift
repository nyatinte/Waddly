import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WaddlyCore

/// Why a pet image set is being committed. A user's own file must always win, so the sample
/// convenience is refused once any pet is already stored, however the current window got there.
enum PetImageCommitSource {
    case userFile
    case sample
}

@MainActor
final class SetupWizardController: NSWindowController, NSWindowDelegate, ObservableObject {
    /// Two setup steps, then a completion screen that hands the pet over to the desktop.
    enum Step: Int {
        case pet
        case monitoring
        case completed
    }

    /// Inline result of "copy the prompt and open ChatGPT". `nil` means the user has not tried yet.
    enum PromptActionFeedback: Equatable {
        case copied
        case copyFailed
        case openFailed
    }

    let localization: LocalizationController
    /// Reuses the permission page after onboarding without reopening character setup or progress.
    let isMonitoringSettings: Bool
    let promptResourcesURL: URL?

    var prompt: String {
        SetupWizardController.loadPrompt(for: localization, resourcesAt: promptResourcesURL)
    }

    /// Reads a sheet without writing anything; a read failure leaves the stored set untouched.
    let onPreviewImage: @MainActor (URL) async -> PetImageSet?
    /// Commits a set the wizard just read; there is no separate confirmation step in the wizard.
    let onConfirmImage: @MainActor (PetImageSet, PetImageCommitSource) async -> Bool
    /// Commits a reviewed draft with the outcome the shared import screen needs. Defaults to deriving
    /// from `onConfirmImage`, so a caller that has not migrated keeps the same behavior.
    let onCommitCharacter: @MainActor (PetImageSet) async -> CharacterCommitOutcome
    let currentPetImages: @MainActor () -> PetImageSet
    /// Owns the permission rules, the waiting, and the System Settings hand-off.
    let permission: PermissionService
    /// The pasteboard the prompt copy writes to. Injectable so tests never touch the system one.
    let pasteboard: NSPasteboard
    /// Opens the ChatGPT URL. Injectable so a test can prove the truthful failure state.
    let openBrowser: @MainActor (URL) -> Bool
    /// Quits and reopens Waddly. Injectable so a test can prove the restart prompt without
    /// terminating the test process.
    let relaunch: @MainActor () -> Void
    /// Announces an inline failure. Injectable so tests prove the call without posting real speech.
    let announce: @MainActor (String) -> Void
    /// The only way this window reaches the screen. Tests pass one that draws nothing.
    let presenter: WindowPresenter

    /// Records the step so a relaunch lands where the user left off. `nil` clears it.
    let onStepChange: @MainActor (Int?) -> Void
    let onShowOnDesktop: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    let previewPane = SetupPreviewPane(frame: .zero)
    var embeddedCharacterPreviewPane: SetupPreviewPane?
    var demoImages: PetImageSet?

    @Published var currentStep = Step.pet
    @Published var isShowingChatGPTGuide = false
    @Published var didRegisterPet = false
    /// Set only when the user explicitly chose the bundled sample, so the page can say which pet
    /// is active. It is session state, like `importedFileName`.
    @Published var didUseSamplePet = false
    @Published var importedFileName: String?
    @Published var promptFeedback: PromptActionFeedback?
    /// Set when a chosen sheet could not be read, so the page can explain it in place.
    @Published var didFailImport = false
    /// Identifies the interaction that may publish asynchronous import feedback.
    var importFeedbackGeneration = UUID()
    /// The confirmation the step last repainted, so a delivered key repaints the page once.
    var didRenderConfirmedReaction = false
    /// The in-flight sample commit, so a rapid second click cannot start a second write.
    var sampleCommitTask: Task<Void, Never>?
    /// How many file imports are between the user's choice and their commit. The sample is refused
    /// while any of them is pending, because a sample commit queued behind one would replace the pet
    /// the user asked for. Published so the shortcut disappears as soon as an import starts instead
    /// of staying visible and ignoring clicks.
    @Published var pendingImportCount = 0
    @Published var isShowingTroubleshooting = false
    /// True while the shared character import screen replaces the method list inside the Pet step.
    @Published var isComposingCharacter = false

    init(
        localization: LocalizationController,
        promptResourcesURL: URL? = Bundle.main.resourceURL,
        demoPetURL: URL? = Bundle.main.url(forResource: "demo-pet", withExtension: "png"),
        onPreviewImage: @escaping @MainActor (URL) async -> PetImageSet?,
        onConfirmImage: @escaping @MainActor (PetImageSet, PetImageCommitSource) async -> Bool,
        onCommitCharacter: (@MainActor (PetImageSet) async -> CharacterCommitOutcome)? = nil,
        currentPetImages: @escaping @MainActor () -> PetImageSet,
        permission: PermissionService,
        presenter: WindowPresenter = .live,
        isMonitoringSettings: Bool = false,
        savedStep: Int? = nil,
        pasteboard: NSPasteboard = .general,
        openBrowser: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        relaunch: @escaping @MainActor () -> Void = SetupWizardController.performRelaunch,
        announce: @escaping @MainActor (String) -> Void = SetupWizardController.postAccessibilityAnnouncement,
        onStepChange: @escaping @MainActor (Int?) -> Void = { _ in },
        onShowOnDesktop: @escaping @MainActor () -> Void = {},
        onClose: @escaping @MainActor () -> Void
    ) {
        self.localization = localization
        self.isMonitoringSettings = isMonitoringSettings
        self.promptResourcesURL = promptResourcesURL
        self.onPreviewImage = onPreviewImage
        self.onConfirmImage = onConfirmImage
        self.onCommitCharacter = onCommitCharacter ?? { images in
            await onConfirmImage(images, .userFile) ? .committed : .rejected
        }
        self.currentPetImages = currentPetImages
        self.permission = permission
        self.pasteboard = pasteboard
        self.openBrowser = openBrowser
        self.relaunch = relaunch
        self.announce = announce
        self.presenter = presenter
        self.onStepChange = onStepChange
        self.onShowOnDesktop = onShowOnDesktop
        self.onClose = onClose
        demoImages = Self.loadDemoImages(from: demoPetURL)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SetupMetrics.contentSize),
            // The layout is designed for one fixed size; letting it stretch only distorted the columns.
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        if isMonitoringSettings {
            currentStep = .monitoring
        } else if let savedStep, let restored = Step(rawValue: savedStep) {
            currentStep = restored
        }
        window.title = localizedString(isMonitoringSettings ? .setupSetUpMonitoring : .setupWindowTitle)
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

    /// The sample shortcut is offered only while the pet store is empty and no file import is still
    /// on its way to a commit, so choosing it can never replace a pet the user asked for. It is
    /// explicit: nothing is written until the user picks it.
    var canTrySample: Bool {
        !hasImage && demoImages != nil && pendingImportCount == 0
    }

    /// The shared acquisition → inspect → commit state machine, created once and rebased every time
    /// the import screen opens. Staging writes nothing; the existing Continue/commit path does.
    lazy var characterImportModel = CharacterImportModel(
        currentImages: { [weak self] in self?.currentPetImages() ?? PetImageSet() },
        commit: { [weak self] images in
            guard let self else { return .rejected }
            return await onCommitCharacter(images)
        }
    )

    var isMonitoringGranted: Bool {
        permission.isGranted
    }

    /// The four progress states the Keyboard reactions step distinguishes: permission missing, tap
    /// unavailable, tap live but no key observed, and a key observed. Only the last is ready.
    var monitoringReadiness: PermissionService.Readiness {
        permission.readiness
    }

    /// True only when permission is granted and a real key has reached Waddly since the tap started.
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

    /// The guide is the one presentation that is not the designed two-column page. While it is on
    /// screen the window is the narrow guide, so it can park beside System Settings without covering
    /// the app list the user is dragging onto; every other page keeps `contentSize`.
    var isCompactGuide: Bool {
        currentStep == .monitoring && isShowingGuide
    }

    var contentSize: NSSize {
        isCompactGuide ? SetupMetrics.compactGuideSize : SetupMetrics.contentSize
    }

    func refreshPermissionStatus() {
        permission.refresh()
        guard currentStep != .pet else { return }
        renderCurrentStep()
    }

    /// The guide follows System Settings until the user moves it.
    private var following = GuideFollowing()
    private var wasShowingGuide = false
    /// The size the window was last given, so a re-render only resizes on a real transition.
    var appliedCompactGuide = false
    private var isMovingProgrammatically = false
    private var isConfirmingWindowClose = false
    private var mayCloseAfterConfirmedDiscard = false

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

    /// The wizard is shown from the app and from tests, so the one window it owns goes through the
    /// presenter here instead of `super`, which would order a real window onto the desktop.
    override func showWindow(_ sender: Any?) {
        guard let window else { return }
        presenter.focus(window)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isMovingProgrammatically, isShowingGuide, let window else { return }
        following.recordMove(to: window.frame.origin)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !characterImportModel.isApplying else { return false }
        if mayCloseAfterConfirmedDiscard {
            return true
        }
        guard isComposingCharacter, characterImportModel.isDirty else { return true }
        guard !isConfirmingWindowClose else { return false }
        isConfirmingWindowClose = true
        guard let window else {
            mayCloseAfterConfirmedDiscard = true
            close()
            return true
        }
        let alert = NSAlert()
        alert.messageText = localizedString(.characterDiscardTitle)
        alert.informativeText = localizedString(.characterDiscardMessage)
        alert.alertStyle = .warning
        alert.addButton(withTitle: localizedString(.characterDiscardConfirm))
        alert.addButton(withTitle: localizedString(.characterCancel))
        presenter.presentAlert(alert, window) { [weak self] response in
            guard let self else { return }
            isConfirmingWindowClose = false
            guard response == .alertFirstButtonReturn, !characterImportModel.isApplying else { return }
            mayCloseAfterConfirmedDiscard = true
            close()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        clearImportFeedback()
        permission.stop()
        window?.level = .normal
        previewPane.stopPlayback()
        stopEmbeddedCharacterPreview()
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

    /// The native macOS announcement API. The wizard calls it only when an inline error appears, so
    /// VoiceOver hears the reason once; re-rendering never re-announces.
    static func postAccessibilityAnnouncement(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSNumber(value: NSAccessibilityPriorityLevel.high.rawValue)
            ]
        )
    }
}

extension SetupWizardController {
    func renderCurrentStep() {
        updateGuidePresentation()
        updatePreview()
        didRenderConfirmedReaction = isMonitoringReady
        objectWillChange.send()
    }

    private func updatePreview() {
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

    /// While reactions cannot work yet, the pet sleeps on the permission step. Once the tap is live
    /// (even before a key arrives), the pet stays awake so the user can watch for the reaction.
    private var shouldSleepInPreview: Bool {
        guard currentStep == .monitoring else { return false }
        switch monitoringReadiness {
        case .permissionMissing, .tapUnavailable: return true
        case .awaitingReaction, .reactionObserved: return false
        }
    }

    /// The completion screen states the outcome, so the stage carries no repeated caption.
    private var previewCaption: String {
        guard currentStep == .monitoring else { return "" }
        switch monitoringReadiness {
        case .reactionObserved: return ""
        case .awaitingReaction: return localizedString(.setupPreviewMonitoringWaiting)
        case .permissionMissing, .tapUnavailable: return localizedString(.setupPreviewMonitoringOff)
        }
    }
}
