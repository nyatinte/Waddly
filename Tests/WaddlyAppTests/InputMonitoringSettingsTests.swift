import AppKit
import Testing
@testable import WaddlyApp

@Suite(.serialized) @MainActor struct InputMonitoringSettingsTests {
    @Test func configuredMenusOpenMonitoringWithoutRewritingSetupOrImages() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        // Retain both menus from before setup completes: AppKit validation must update copied items too.
        let statusItem = try setupItem(in: app.statusMenu)
        let contextItem = try setupItem(in: app.makePetContextMenu())
        #expect(statusItem.title == app.localizedString(.menuSetupWizard))
        try await app.persistPetImages(fixture.exampleImages())
        app.settings.setupWizardSeen = true
        app.settings.setupStep = nil
        let saved = try fixture.savedData()

        for item in [statusItem, contextItem] {
            #expect(app.validateMenuItem(item))
            #expect(item.title == app.localizedString(.menuInputMonitoring))
            #expect(try NSApp.sendAction(#require(item.action), to: item.target, from: item))
            let wizard = try #require(app.setupWizardController)
            #expect(wizard.isMonitoringSettings)
            #expect(wizard.currentStep == .monitoring)
            #expect(wizard.window?.title == app.localizedString(.setupSetUpMonitoring))
            #expect(wizard.window?.contentView?.registeredDraggedTypes.isEmpty == true)
            #expect(wizard.previewPane.registeredDraggedTypes.isEmpty)
            wizard.goBack()
            wizard.showMonitoringStep()
            wizard.handleWindowDrop([fixture.exampleURL])
            #expect(wizard.currentStep == .monitoring)
            #expect(wizard.pendingImportCount == 0)
            #expect(!wizard.isComposingCharacter)
            #expect(app.settings.setupStep == nil)
            wizard.goNext() // Close is available regardless of permission/readiness.
            #expect(app.setupWizardController == nil)
            #expect(app.isSetupComplete)
            #expect(app.settings.setupStep == nil)
            #expect(try fixture.savedData() == saved)
        }
    }

    @Test(arguments: [SetupWizardController.Step.pet, .monitoring, .completed])
    func unfinishedSetupKeepsItsMenuAndSavedStep(step: SetupWizardController.Step) async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.settings.setupWizardSeen = true
        app.settings.setupStep = step.rawValue
        let item = try setupItem(in: app.statusMenu)
        #expect(app.validateMenuItem(item))
        #expect(item.title == app.localizedString(.menuSetupWizard))
        #expect(try NSApp.sendAction(#require(item.action), to: item.target, from: item))
        let wizard = try #require(app.setupWizardController)
        #expect(!wizard.isMonitoringSettings)
        #expect(wizard.currentStep == step)
        wizard.close()
        #expect(app.settings.setupStep == step.rawValue)
        #expect(!app.isSetupComplete)
    }

    @Test func firstRunStillStartsWithCharacterSetup() throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        let item = try setupItem(in: app.statusMenu)
        #expect(app.validateMenuItem(item))
        #expect(item.title == app.localizedString(.menuSetupWizard))
        #expect(try NSApp.sendAction(#require(item.action), to: item.target, from: item))
        #expect(app.setupWizardController?.isMonitoringSettings == false)
        #expect(app.setupWizardController?.currentStep == .pet)
        app.setupWizardController?.close()
        #expect(!app.settings.setupWizardSeen)
    }

    @Test(arguments: [AppLanguage.japanese, .english], [
        PermissionService.Readiness.permissionMissing, .tapUnavailable, .awaitingReaction, .reactionObserved
    ])
    func permissionPageKeepsAllReadinessAndRecoveryStates(
        language: AppLanguage, readiness: PermissionService.Readiness
    ) throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        var steps: [Int?] = []
        var reveals = 0
        let wizard = try Fixture.makeWizard(
            language: language,
            state: state,
            savedStep: SetupWizardController.Step.pet.rawValue,
            granted: readiness != .permissionMissing,
            receiving: readiness != .tapUnavailable,
            observedReaction: readiness == .reactionObserved,
            requestPermission: { state.granted },
            isMonitoringSettings: true,
            onStepChange: { steps.append($0) },
            onShowOnDesktop: { reveals += 1 }
        )
        defer { wizard.close() }
        wizard.showWindow(nil)
        #expect(wizard.currentStep == .monitoring)
        #expect(wizard.monitoringReadiness == readiness)
        #expect(wizard.isMonitoringReady == (readiness == .reactionObserved))
        #expect(wizard.window?.title == wizard.localizedString(.setupSetUpMonitoring))
        wizard.refreshLocalization()
        #expect(wizard.window?.title == wizard.localizedString(.setupSetUpMonitoring))
        wizard.goBack()
        #expect(wizard.currentStep == .monitoring)
        #expect(steps.isEmpty)
        if readiness == .permissionMissing {
            wizard.enableMonitoring()
            #expect(wizard.isShowingGuide)
            #expect(state.settingsOpened == 1)
            wizard.toggleManualSteps()
            #expect(wizard.isShowingManualSteps)
        } else {
            wizard.retryMonitoring()
            #expect(state.tapRestarted == 1)
            wizard.toggleTroubleshooting()
            #expect(wizard.isShowingTroubleshooting)
        }
        wizard.goNext()
        #expect(state.closed)
        #expect(steps.isEmpty)
        #expect(reveals == 0)
        #expect(state.commitCharacterCount == 0)
        #expect(state.confirmCount == 0)
    }

    private func setupItem(in menu: NSMenu) throws -> NSMenuItem {
        try #require(menu.items.first { $0.action == #selector(AppDelegate.showSetupWizard) })
    }

    /// The guide is the narrow one: it parks beside System Settings so the app list stays visible,
    /// and it goes back to the designed window as soon as the permission arrives.
    @Test func guideUsesTheCompactWindowAndRestoresTheDesignedOne() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(
            state: state,
            granted: false,
            requestPermission: { false },
            isMonitoringSettings: true
        )
        defer { wizard.close() }
        let window = try #require(wizard.window)
        #expect(!wizard.isCompactGuide)
        #expect(window.contentView?.bounds.size == SetupMetrics.contentSize)

        wizard.enableMonitoring()
        #expect(wizard.isShowingGuide)
        #expect(wizard.isCompactGuide)
        #expect(window.contentView?.bounds.size == SetupMetrics.compactGuideSize)

        // The manual fallback is the same guide presentation.
        wizard.toggleManualSteps()
        #expect(wizard.isCompactGuide)
        #expect(window.contentView?.bounds.size == SetupMetrics.compactGuideSize)

        state.granted = true
        wizard.refreshPermissionStatus()
        #expect(!wizard.isShowingGuide)
        #expect(!wizard.isCompactGuide)
        #expect(window.contentView?.bounds.size == SetupMetrics.contentSize)
    }
}
