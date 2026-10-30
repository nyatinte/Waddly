import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct SetupActivationTests {
    /// Cmd+Tab only sends `didBecomeActive`, so a guide the user had closed comes back at its step.
    @Test func closedGuideComesBackAtTheSavedStep() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.settings.setupWizardSeen = true
        app.settings.setupStep = SetupWizardController.Step.monitoring.rawValue
        app.showSetupWizard()
        app.setupWizardController?.close()
        #expect(app.setupWizardController == nil)

        app.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        #expect(app.setupWizardController?.window?.isVisible == true)
        #expect(app.setupWizardController?.currentStep == .monitoring)
    }

    /// Activation is not a reopen: an open guide stays, and a finished setup is never reopened.
    @Test func openGuideAndFinishedSetupAreLeftAlone() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        app.showSetupWizard()
        let wizard = try #require(app.setupWizardController)
        app.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        #expect(app.setupWizardController === wizard)
        #expect(wizard.window?.isVisible == true)

        try await app.persistPetImages(fixture.exampleImages())
        app.settings.setupWizardSeen = true
        app.settings.setupStep = nil
        wizard.close()
        #expect(app.setupWizardController == nil)
        app.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        #expect(app.setupWizardController == nil)
    }
}
