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

    @MainActor
    static func sheetImages() throws -> PetImageSet {
        try #require(try PetSpriteSheetImporter.frames(from: Data(contentsOf: sheetURL())))
    }

    @MainActor
    static func optionCard(_ action: String, in content: NSView) throws -> SetupOptionCard {
        try #require(descendants(of: content).compactMap { $0 as? SetupOptionCard }
            .first { $0.actionSelector == NSSelectorFromString(action) })
    }

    @MainActor
    static func button(_ action: String, in content: NSView) throws -> NSButton {
        try #require(descendants(of: content).compactMap { $0 as? NSButton }
            .first { $0.action == NSSelectorFromString(action) })
    }

    @MainActor
    static func makeWizard(
        language: AppLanguage = .japanese,
        state: State = State(),
        demoURL: URL? = nil,
        savedStep: Int? = nil,
        granted: Bool = false,
        previewResult: PetImageSet? = nil,
        confirmResult: Bool = false,
        requestPermission: @escaping @MainActor () -> Bool = { false },
        onPermissionService: @MainActor (PermissionService) -> Void = { _ in },
        onStepChange: @escaping @MainActor (Int?) -> Void = { _ in },
        onShowOnDesktop: @escaping @MainActor () -> Void = {}
    ) throws -> SetupWizardController {
        _ = NSApplication.shared
        let name = "WaddlyTests.wizard.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = AppSettings(defaults: defaults)
        settings.appLanguage = language
        state.previewResult = previewResult
        state.confirmResult = confirmResult
        // The wizard no longer knows about CGPreflight or event taps; the service does.
        let permission = PermissionService(
            hasPermission: { state.granted },
            isReceivingKeys: { state.granted },
            requestAccess: { requestPermission() },
            restartTap: { state.tapRestarted += 1 },
            openSettings: { state.settingsOpened += 1 }
        )
        state.granted = granted
        onPermissionService(permission)
        let resources = try #require(Bundle(url: root().appendingPathComponent("macos")))
        return SetupWizardController(
            localization: LocalizationController(settings: settings, resources: resources),
            demoPetURL: demoURL,
            onPreviewImage: { _ in state.previewResult },
            onConfirmImage: { images in
                // Mirrors the app: committing is what updates the stored set.
                if state.confirmResult {
                    state.images = images
                }
                return state.confirmResult
            },
            currentPetImages: { state.images },
            permission: permission,
            savedStep: savedStep,
            onStepChange: onStepChange,
            onShowOnDesktop: onShowOnDesktop,
            onClose: {
                defaults.removePersistentDomain(forName: name)
                state.closed = true
            }
        )
    }

    @MainActor
    static func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    /// Waits for an async wizard action to settle without hard-coding a delay.
    @MainActor
    static func waitUntil(_ condition: () -> Bool, attempts: Int = 400) async throws {
        for _ in 0 ..< attempts {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("condition never became true")
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
        /// What `onPreviewImage` returns; `nil` models an unreadable file.
        var previewResult: PetImageSet?
        var confirmResult = false
        var granted = false
        var tapRestarted = 0
        var settingsOpened = 0
    }
}
