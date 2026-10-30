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

    @Test(arguments: [false, true])
    func earlySetupReceivesRestoredImagesWithoutOverwritingDraft(stageSample: Bool) async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        try await fixture.app.persistPetImages(fixture.exampleImages())

        let app = AppDelegate(settings: AppSettings(defaults: fixture.defaults), presenter: .invisible)
        app.petImagesDirectoryURL = fixture.directory
        app.buildPanel()
        app.buildMenu()
        defer {
            app.setupWizardController?.characterImportModel.discard()
            app.setupWizardController?.close()
            app.monitor.stop()
            app.animationController.shutdown()
            app.panel.close()
            NSStatusBar.system.removeStatusItem(app.statusItem)
        }
        app.settings.setupWizardSeen = false
        app.settings.setupStep = SetupWizardController.Step.pet.rawValue
        app.showSetupWizard()
        let wizard = try #require(app.setupWizardController)
        #expect(!wizard.characterImportModel.hasStagedCandidate)

        let sample = try fixture.exampleImages()
        if stageSample {
            wizard.characterImportModel.stageSample(sample, name: "Sample")
        }
        await app.loadSavedPetImage()
        #expect(wizard.characterImportModel.canApply)
        if stageSample {
            #expect(wizard.characterImportModel.stagedFrames?[.idle].first === sample[.idle].first)
            #expect(wizard.characterImportModel.isSampleCandidate)
        } else {
            #expect(wizard.characterImportModel.stagedFrames?[.idle].first === app.petImages[.idle].first)
            #expect(!wizard.characterImportModel.isDirty)
        }
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
