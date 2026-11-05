import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// First-run journey coverage: the sample shortcut, and the progress that survives an interrupted
/// permission hand-off. Kept apart from `SetupWizardTests` so each suite stays readable.
@Suite(.serialized) @MainActor struct SetupWizardJourneyTests {
    @Test func sharedScreenStagesSampleUntilNext() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(state: state, demoURL: Fixture.sheetURL(), confirmResult: true)
        defer { wizard.close() }
        let sample = try #require(wizard.demoImages)
        wizard.characterImportModel.stageSample(sample, name: "Sample")
        #expect(wizard.characterImportModel.hasStagedCandidate)
        #expect(wizard.characterImportModel.isDirty)
        #expect(state.confirmCount == 0)
        #expect(!wizard.hasImage)
        await wizard.commitCharacterImportAndContinue().value
        #expect(state.confirmCount == 1)
        #expect(wizard.hasImage)
        #expect(wizard.currentStep == .monitoring)
    }

    @Test func discardingStagedSampleDoesNotSaveIt() throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(state: state, demoURL: Fixture.sheetURL())
        defer { wizard.close() }
        let sample = try #require(wizard.demoImages)
        wizard.characterImportModel.stageSample(sample, name: "Sample")
        wizard.characterImportModel.discard()
        #expect(state.confirmCount == 0)
        #expect(!wizard.characterImportModel.hasStagedCandidate)
        #expect(!wizard.hasImage)
    }

    /// Closing part-way keeps the saved step. On relaunch macOS has applied the grant, but the tap
    /// has not started yet: the resumed page must say "restart required", not a false ready state.
    @Test func interruptedPermissionFlowResumesToRestartRequired() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(
            state: state,
            savedStep: SetupWizardController.Step.monitoring.rawValue,
            granted: true,
            receiving: false
        )
        defer { wizard.close() }
        #expect(wizard.currentStep == .monitoring)
        #expect(wizard.isMonitoringGranted)
        #expect(!wizard.isMonitoringReady)

        // Next stays blocked while the keyboard is silent.
        wizard.goNext()
        #expect(wizard.currentStep == .monitoring)

        // The tap comes back on the same run, so the step can finish truthfully.
        state.receiving = true
        wizard.refreshPermissionStatus()
        #expect(wizard.isMonitoringReady)
        wizard.goNext()
        #expect(wizard.currentStep == .completed)
    }

    @Test func deferringSavesTheReadyStepSoARelaunchCanResume() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        var recorded: [Int?] = []
        let wizard = try Fixture.makeWizard(
            state: state,
            savedStep: SetupWizardController.Step.monitoring.rawValue,
            onStepChange: { recorded.append($0) }
        )
        defer { wizard.close() }

        wizard.deferMonitoring()
        #expect(wizard.currentStep == .completed)
        #expect(recorded.last == SetupWizardController.Step.completed.rawValue)
        #expect(wizard.hasImage)

        // Reopening the guide (Dock click or menu) lands on the completion page with the
        // missing-permission warning still shown. A launch with this unfinished step reopens the
        // guide by itself at the saved page.
        let resumed = try Fixture.makeWizard(
            state: state,
            savedStep: SetupWizardController.Step.completed.rawValue
        )
        defer { resumed.close() }
        #expect(resumed.currentStep == .completed)
        #expect(!resumed.isMonitoringReady)
        resumed.showMonitoringStep()
        #expect(resumed.currentStep == .monitoring)
    }

    /// A granted permission that needs a restart is repaired from the completion page, where the
    /// user lands after choosing "Set up later" — not by sending them back to "enable" it again.
    @Test func restartRequiredOffersRestartFromTheCompletionPage() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        var relaunches = 0
        let wizard = try Fixture.makeWizard(
            state: state,
            savedStep: SetupWizardController.Step.monitoring.rawValue,
            granted: true,
            receiving: false,
            relaunch: { relaunches += 1 }
        )
        defer { wizard.close() }

        wizard.deferMonitoring()

        #expect(wizard.currentStep == .completed)
        #expect(wizard.monitoringReadiness == .tapUnavailable)
        #expect(!wizard.isMonitoringReady)
        #expect(wizard.monitoringRecovery == .restart)
        #expect(wizard.monitoringCheckKey == .setupCheckMonitoringRestart)
        #expect(wizard.monitoringIncompleteWarningKey == .setupCompleteWarningRestart)
        #expect(wizard.monitoringIncompleteActionKey == .setupRestartNow)

        wizard.relaunchApp()
        #expect(relaunches == 1)
    }

    /// A live tap with zero delivered keys must stay unconfirmed: no success, no advance.
    @Test func aLiveTapStaysUnconfirmedUntilAKeyArrives() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(
            state: state,
            savedStep: SetupWizardController.Step.monitoring.rawValue,
            granted: true,
            receiving: true,
            observedReaction: false
        )
        defer { wizard.close() }
        #expect(wizard.monitoringReadiness == .awaitingReaction)
        #expect(wizard.isMonitoringGranted)
        #expect(!wizard.isMonitoringReady)

        wizard.goNext()
        #expect(wizard.currentStep == .monitoring)

        // The delivered-key callback repaints the step, and only then is it ready.
        state.observedReaction = true
        wizard.monitoringDidObserveReaction(isEnter: false)
        #expect(wizard.monitoringReadiness == .reactionObserved)
        #expect(wizard.isMonitoringReady)
        wizard.goNext()
        #expect(wizard.currentStep == .completed)
    }

    /// "Set up later" with a live-but-unconfirmed tap stays incomplete, and the completion page
    /// offers to confirm typing rather than to set permissions up again.
    @Test func deferringFromALiveTapKeepsTheCheckWaiting() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(
            state: state,
            savedStep: SetupWizardController.Step.monitoring.rawValue,
            granted: true,
            receiving: true,
            observedReaction: false
        )
        defer { wizard.close() }

        wizard.deferMonitoring()

        #expect(wizard.currentStep == .completed)
        #expect(!wizard.isMonitoringReady)
        #expect(wizard.monitoringCheckKey == .setupCheckMonitoringWaiting)
        #expect(wizard.monitoringIncompleteActionKey == .setupConfirmTyping)
        #expect(wizard.monitoringRecovery == .confirmTyping)

        // A delivered key confirms it from the completion page too.
        state.observedReaction = true
        wizard.monitoringDidObserveReaction(isEnter: false)
        #expect(wizard.isMonitoringReady)
        #expect(wizard.monitoringCheckKey == .setupCheckMonitoring)
    }

    /// A returning user who already confirmed reactions is not reset by reopening the guide.
    @Test func aReturningUserKeepsAConfirmedReaction() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(
            state: state,
            savedStep: SetupWizardController.Step.completed.rawValue,
            granted: true,
            receiving: true,
            observedReaction: true
        )
        defer { wizard.close() }

        #expect(wizard.currentStep == .completed)
        #expect(wizard.isMonitoringReady)
        #expect(wizard.monitoringCheckKey == .setupCheckMonitoring)
        wizard.renderCurrentStep()
        #expect(wizard.isMonitoringReady)
    }
}
