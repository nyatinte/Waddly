import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Shared scaffolding for the setup wizard suites. Kept out of the suites so their bodies stay short.
enum SetupWizardFixture {
    @MainActor
    static func sheetURL() throws -> URL {
        root().appendingPathComponent("assets/examples/nyatinte-bot-3x3.png")
    }

    /// The nine frame images alone, without the sheet-source editing metadata. Tests that need the
    /// staged source use `sheetCandidate()` or the real loader; this fixture keeps the plain frame
    /// set that older coverage assumes.
    @MainActor
    static func sheetImages() throws -> PetImageSet {
        let candidate = try sheetCandidate()
        var images = PetImageSet()
        for category in PetImageCategory.allCases {
            images[category] = candidate.images[category]
        }
        return images
    }

    @MainActor
    static func sheetCandidate() throws -> PetSheetCandidate {
        try #require(try? PetSpriteSheetImporter.inspect(Data(contentsOf: sheetURL())).get())
    }

    @MainActor
    static func makeWizard(
        language: AppLanguage = .japanese,
        state: State = State(),
        demoURL: URL? = nil,
        savedStep: Int? = nil,
        granted: Bool = false,
        receiving: Bool = true,
        observedReaction: Bool = true,
        confirmResult: Bool = false,
        commitCharacterOutcome: CharacterCommitOutcome? = nil,
        commitCharacter: (@MainActor (PetImageSet) async -> CharacterCommitOutcome)? = nil,
        requestPermission: @escaping @MainActor () -> Bool = { false },
        openBrowser: @escaping @MainActor (URL) -> Bool = { _ in true },
        relaunch: @escaping @MainActor () -> Void = {},
        onPermissionService: @MainActor (PermissionService) -> Void = { _ in },
        presenter: WindowPresenter = .invisible,
        isMonitoringSettings: Bool = false,
        onStepChange: @escaping @MainActor (Int?) -> Void = { _ in },
        onShowOnDesktop: @escaping @MainActor () -> Void = {}
    ) throws -> SetupWizardController {
        _ = NSApplication.shared
        let name = "WaddlyTests.wizard.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = AppSettings(defaults: defaults)
        settings.appLanguage = language
        state.confirmResult = confirmResult
        state.granted = granted
        state.receiving = receiving
        state.observedReaction = observedReaction
        let permission = makePermission(state: state, requestPermission: requestPermission)
        onPermissionService(permission)
        let resources = try #require(Bundle(url: root().appendingPathComponent("macos")))
        // A named pasteboard keeps the prompt copy off the system clipboard in every run.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WaddlyTests.wizard.\(UUID().uuidString)"))
        return SetupWizardController(
            localization: LocalizationController(settings: settings, resources: resources),
            promptResourcesURL: root(),
            demoPetURL: demoURL,
            onCommitCharacter: { images, source in
                guard AppDelegate.shouldCommitPetImages(source: source, petIsStored: state.images.isComplete) else {
                    return .rejected
                }
                if source == .sample {
                    state.confirmCount += 1
                    guard state.confirmResult else { return .rejected }
                    state.images = images
                    return .committed
                }
                let commit = commitCharacter ?? makeCommitCharacter(state: state, outcome: commitCharacterOutcome)
                return await commit(images)
            },
            currentPetImages: { state.images },
            permission: permission,
            presenter: presenter,
            isMonitoringSettings: isMonitoringSettings,
            savedStep: savedStep,
            pasteboard: pasteboard,
            openBrowser: openBrowser,
            relaunch: relaunch,
            announce: { state.announcements.append($0) },
            onStepChange: onStepChange,
            onShowOnDesktop: onShowOnDesktop,
            onClose: {
                defaults.removePersistentDomain(forName: name)
                state.closed = true
            }
        )
    }

    @MainActor
    private static func makeCommitCharacter(
        state: State,
        outcome: CharacterCommitOutcome?
    ) -> @MainActor (PetImageSet) async -> CharacterCommitOutcome {
        { images in
            state.commitCharacterCount += 1
            guard let outcome else {
                state.images = images
                return .committed
            }
            if outcome == .committed {
                state.images = images
            }
            return outcome
        }
    }

    /// The wizard no longer knows about CGPreflight or event taps; the service does.
    @MainActor
    private static func makePermission(
        state: State,
        requestPermission: @escaping @MainActor () -> Bool
    ) -> PermissionService {
        PermissionService(
            hasPermission: { state.granted },
            isReceivingKeys: { state.granted && state.receiving },
            hasObservedReaction: { state.observedReaction },
            requestAccess: { requestPermission() },
            restartTap: { state.tapRestarted += 1 },
            openSettings: { state.settingsOpened += 1 }
        )
    }

    @MainActor
    static func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    @MainActor
    static func root() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @MainActor
    final class State {
        var images = PetImageSet()
        var closed = false
        var confirmResult = false
        var granted = false
        /// Whether the granted app is actually receiving keys; `false` is the restart-required state.
        var receiving = true
        /// Whether a real key has been delivered since the tap started; `false` is the live-tap but
        /// no-reaction-yet state.
        var observedReaction = true
        var tapRestarted = 0
        var settingsOpened = 0
        /// How many times the wizard committed an image set; a duplicate sample click must stay at 1.
        var confirmCount = 0
        /// How many times the shared character screen committed a reviewed draft.
        var commitCharacterCount = 0
        /// Messages the wizard asked to announce; the fixture records them instead of speaking.
        var announcements: [String] = []
    }
}
