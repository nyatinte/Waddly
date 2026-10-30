import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WaddlyCore

@MainActor
final class SetupWizardController: NSWindowController, NSWindowDelegate, ObservableObject {
    /// Two setup steps, then a completion screen that hands the pet over to the desktop.
    enum Step: Int {
        case pet
        case monitoring
        case completed
    }

    let localization: LocalizationController
    /// Reuses the permission page after onboarding without reopening character setup or progress.
    let isMonitoringSettings: Bool
    let promptResourcesURL: URL?

    let onCommitCharacter: @MainActor (PetImageSet, PetImageCommitSource) async -> CharacterCommitOutcome
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
    /// The confirmation the step last repainted, so a delivered key repaints the page once.
    var didRenderConfirmedReaction = false
    @Published var isShowingTroubleshooting = false
    var isComposingCharacter: Bool {
        !isMonitoringSettings && currentStep == .pet
    }

    init(
        localization: LocalizationController,
        promptResourcesURL: URL? = Bundle.main.resourceURL,
        demoPetURL: URL? = Bundle.main.url(forResource: "demo-pet", withExtension: "png"),
        onCommitCharacter: @escaping @MainActor (PetImageSet, PetImageCommitSource) async -> CharacterCommitOutcome,
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
        self.onCommitCharacter = onCommitCharacter
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

    var canTrySample: Bool {
        !hasImage && demoImages != nil
    }

    lazy var characterImportModel = CharacterImportModel(
        currentImages: { [weak self] in self?.currentPetImages() ?? PetImageSet() },
        commit: { [weak self] images in
            guard let self else { return .rejected }
            return await commitCharacterDraft(images)
        }
    )

    private func commitCharacterDraft(_ images: PetImageSet) async -> CharacterCommitOutcome {
        let source: PetImageCommitSource = characterImportModel.isSampleCandidate ? .sample : .userFile
        return await onCommitCharacter(images, source)
    }

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
        if let contentView = window?.contentView as? PetImageDropView {
            if isComposingCharacter {
                contentView.registerForDraggedTypes([.fileURL])
            } else {
                contentView.unregisterDraggedTypes()
            }
        }
        updatePreview()
        didRenderConfirmedReaction = isMonitoringReady
        objectWillChange.send()
    }

    private func updatePreview() {
        previewPane.setReactionTest(currentStep == .monitoring)
        let images = currentPetImages()
        if images.isComplete {
            previewPane.showPet(images, caption: previewCaption, sleeping: shouldSleepInPreview)
        } else if let demoImages {
            previewPane.showDemo(demoImages)
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
