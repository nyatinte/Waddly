import AppKit
import Testing
@testable import WaddlyApp

@Suite(.serialized) @MainActor struct PermissionGuideKeyboardTests {
    private func key(_ characters: String, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0
        ))
    }

    @Test(arguments: [AppLanguage.english, .japanese])
    func waitingInstructionsDoNotAssumeAPreviewBesideTheGuide(language: AppLanguage) throws {
        let wizard = try SetupWizardFixture.makeWizard(language: language, isMonitoringSettings: true)
        defer { wizard.close() }
        let text = wizard.localizedString(.setupMonitoringWaitingBody)
        #expect(!text.contains("right"))
        #expect(!text.contains("右"))
        #expect(!text.isEmpty)
    }

    @Test(arguments: [NSEvent.ModifierFlags.command, [.command, .capsLock]])
    func guideAcceptsFocusAndCommandWClosesThroughTheWindowDelegate(modifiers: NSEvent.ModifierFlags) throws {
        let state = SetupWizardFixture.State()
        let wizard = try SetupWizardFixture.makeWizard(state: state, isMonitoringSettings: true)
        let controller = PermissionGuidePanelController(wizard: wizard)
        let panel = try #require(controller.window as? PermissionGuidePanel)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.becomesKeyOnlyIfNeeded)
        #expect(try !panel.performKeyEquivalent(with: key("w", modifiers: [.command, .shift])))
        #expect(!state.closed)
        #expect(try panel.performKeyEquivalent(with: key("w", modifiers: modifiers)))
        #expect(state.closed)
    }
}
