import AppKit
import Testing
@testable import WaddlyApp

/// First-run journey coverage: the sample shortcut, and the progress that survives an interrupted
/// permission hand-off. Kept apart from `SetupWizardTests` so each suite stays readable.
@Suite(.serialized) @MainActor struct SetupWizardJourneyTests {
    @Test func tryingTheSampleCommitsTheBundledSampleInPlace() async throws {
        let state = Fixture.State()
        var recorded: [Int?] = []
        let wizard = try Fixture.makeWizard(
            state: state,
            demoURL: Fixture.sheetURL(),
            confirmResult: true,
            onStepChange: { recorded.append($0) }
        )
        defer { wizard.close() }
        #expect(wizard.canTrySample)
        #expect(!wizard.hasImage)

        await wizard.trySamplePet().value

        #expect(wizard.didUseSamplePet)
        #expect(wizard.didRegisterPet)
        #expect(wizard.hasImage)
        #expect(wizard.importedFileName == nil)
        // Choosing the sample is a pet choice, not a step change: progress stays untouched.
        #expect(wizard.currentStep == .pet)
        #expect(recorded.isEmpty)
        #expect(!wizard.canTrySample)
        #expect(wizard.previewPane.hasPet)
    }

    @Test func tryingTheSampleNeverReplacesAnExistingPet() async throws {
        let state = Fixture.State()
        let own = try Fixture.sheetImages()
        state.images = own
        let wizard = try Fixture.makeWizard(
            state: state,
            demoURL: Fixture.sheetURL(),
            confirmResult: true
        )
        defer { wizard.close() }
        // The shortcut is not offered while a pet is stored, and a stray call writes nothing.
        #expect(!wizard.canTrySample)
        await wizard.trySamplePet().value
        #expect(!wizard.didUseSamplePet)
        #expect(wizard.currentPetImages()[.idle].first === own[.idle].first)
    }

    @Test func importingARealSheetClearsTheSampleChoice() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(
            state: state,
            demoURL: Fixture.sheetURL(),
            previewResult: Fixture.sheetImages(),
            confirmResult: true
        )
        defer { wizard.close() }
        await wizard.trySamplePet().value
        #expect(wizard.didUseSamplePet)

        let sheetURL = try Fixture.sheetURL()
        await wizard.importImage(from: sheetURL).value
        #expect(!wizard.didUseSamplePet)
        #expect(wizard.importedFileName == sheetURL.lastPathComponent)
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

        // A relaunch lands on the completion page with the missing-permission warning still shown.
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
}
