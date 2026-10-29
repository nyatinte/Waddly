import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp
import WaddlyCore

typealias Fixture = SetupWizardFixture

@Suite(.serialized) @MainActor struct SetupWizardTests {
    @Test(arguments: [AppLanguage.japanese, .english])
    func hostsSwiftUIAndKeepsItsDesignedWindowSize(language: AppLanguage) throws {
        let wizard = try Fixture.makeWizard(language: language, demoURL: Fixture.sheetURL())
        defer { wizard.close() }
        let window = try #require(wizard.window)
        #expect(window.contentView?.subviews.contains { $0 is NSHostingView<SetupWizardScreen> } == true)
        #expect(window.contentView?.bounds.size == SetupMetrics.contentSize)
        #expect(wizard.previewPane.hasPet)
        #expect(!wizard.hasImage)
        for step in [SetupWizardController.Step.pet, .monitoring, .completed] {
            wizard.currentStep = step
            wizard.renderCurrentStep()
            window.layoutIfNeeded()
            #expect(window.contentView?.bounds.size == SetupMetrics.contentSize)
        }
    }

    @Test func stepChangesPersistAndFinishHandsThePetToTheDesktop() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        var recorded: [Int?] = []
        var revealed = false
        let wizard = try Fixture.makeWizard(
            state: state,
            onStepChange: { recorded.append($0) },
            onShowOnDesktop: { revealed = true }
        )
        defer { wizard.close() }

        wizard.goNext()
        #expect(wizard.currentStep == .monitoring)
        #expect(recorded.last == SetupWizardController.Step.monitoring.rawValue)
        wizard.goNext()
        #expect(wizard.currentStep == .monitoring)
        wizard.deferMonitoring()
        #expect(wizard.currentStep == .completed)
        #expect(recorded.last == SetupWizardController.Step.completed.rawValue)
        #expect(!wizard.isMonitoringReady)
        wizard.goNext()
        #expect(recorded.last == .some(nil))
        #expect(revealed)
        #expect(state.closed)
    }

    @Test func setupCannotAdvanceWithoutAnImage() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        wizard.goNext()
        #expect(wizard.currentStep == .pet)
        #expect(!wizard.hasImage)
    }

    @Test func permissionActionEntersTheGuideAndManualFallback() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(state: state, requestPermission: { false })
        defer { wizard.close() }
        wizard.goNext()
        wizard.enableMonitoring()
        #expect(wizard.isShowingGuide)
        wizard.toggleManualSteps()
        #expect(wizard.isShowingManualSteps)
        #expect(wizard.isShowingGuide)
        wizard.toggleManualSteps()
        #expect(!wizard.isShowingManualSteps)
    }

    @Test func importUpdatesTheSwiftUIObservedStateWithoutChangingTheStep() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(
            state: state,
            previewResult: Fixture.sheetImages(),
            confirmResult: true
        )
        defer { wizard.close() }
        let sheetURL = try Fixture.sheetURL()
        await wizard.importImage(from: sheetURL).value
        #expect(wizard.currentStep == .pet)
        #expect(wizard.didRegisterPet)
        #expect(wizard.importedFileName == sheetURL.lastPathComponent)
        #expect(wizard.previewPane.hasPet)
    }

    @Test func savedStepCanBeRestoredAndDismissed() throws {
        let wizard = try Fixture.makeWizard(savedStep: SetupWizardController.Step.monitoring.rawValue)
        defer { wizard.close() }
        #expect(wizard.currentStep == .monitoring)

        wizard.goBack()
        #expect(wizard.currentStep == .pet)
    }

    @Test func troubleshootingStaysInTheWizard() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(state: state, granted: true, requestPermission: { true })
        defer { wizard.close() }
        wizard.currentStep = .monitoring
        wizard.toggleTroubleshooting()
        #expect(wizard.isShowingTroubleshooting)
        #expect(wizard.currentStep == .monitoring)
        #expect(!wizard.isShowingGuide)
    }

    @Test func closingTheWindowStopsPreviewAndAReopenedWizardCanResumeIt() throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(state: state, demoURL: Fixture.sheetURL())
        defer { wizard.close() }
        let firstWindow = try #require(wizard.window)
        wizard.showWindow(nil)
        #expect(wizard.previewPane.isPlayingPreview)

        firstWindow.close()
        #expect(state.closed)
        #expect(!wizard.previewPane.isPlayingPreview)
        #expect(firstWindow.contentView == nil)

        let reopened = try Fixture.makeWizard(demoURL: Fixture.sheetURL())
        defer { reopened.close() }
        reopened.showWindow(nil)
        #expect(reopened.previewPane.isPlayingPreview)
    }

    @Test func failedImportExplainsTheProblemInlineAndKeepsThePreviousSet() async throws {
        let state = Fixture.State()
        let previous = try Fixture.sheetImages()
        state.images = previous
        let wizard = try Fixture.makeWizard(state: state, previewResult: nil)
        defer { wizard.close() }
        try await wizard.importImage(from: Fixture.sheetURL()).value
        #expect(wizard.didFailImport)
        #expect(wizard.currentStep == .pet)
        // The failed read writes nothing, so the seeded set and its preview survive untouched.
        #expect(wizard.hasImage)
        #expect(wizard.currentPetImages()[.idle].first === previous[.idle].first)
        #expect(wizard.previewPane.hasPet)
        #expect(!wizard.didRegisterPet)
        #expect(state.announcements == [wizard.localizedString(.petImportErrorMessage)])

        // Choosing a method again clears the stale message.
        wizard.beginCharacterImport()
        #expect(!wizard.didFailImport)
        wizard.cancelCharacterImport()
    }

    @Test func importFailureStaysOnItsStepAndClearsWhenTheStepChanges() async throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(state: state, previewResult: nil)
        defer { wizard.close() }
        // The drop target is window-wide, so a failure on a later step must stay visible there.
        wizard.setStep(.monitoring)
        try await wizard.importImage(from: Fixture.sheetURL()).value
        #expect(wizard.currentStep == .monitoring)
        #expect(wizard.didFailImport)
        #expect(wizard.hasImage)

        wizard.goBack()
        #expect(wizard.currentStep == .pet)
        #expect(!wizard.didFailImport)
    }

    @Test func permissionGrantedAndReadyStayDistinctStates() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(state: state, granted: false, receiving: false)
        defer { wizard.close() }
        wizard.setStep(.monitoring)

        // 1. Not granted: setup stays on the page.
        #expect(!wizard.isMonitoringGranted)
        #expect(!wizard.isMonitoringReady)
        wizard.goNext()
        #expect(wizard.currentStep == .monitoring)

        // 2. Granted but the keyboard is not arriving: restart required, not success.
        state.granted = true
        state.receiving = false
        wizard.refreshPermissionStatus()
        #expect(wizard.isMonitoringGranted)
        #expect(!wizard.isMonitoringReady)
        wizard.goNext()
        #expect(wizard.currentStep == .monitoring)

        // 3. Granted and receiving keys: ready, and setup can finish.
        state.receiving = true
        wizard.refreshPermissionStatus()
        #expect(wizard.isMonitoringReady)
        wizard.goNext()
        #expect(wizard.currentStep == .completed)
    }
}
