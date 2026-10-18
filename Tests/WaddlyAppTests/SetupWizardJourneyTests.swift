import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

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

        // Reopening the guide (Dock click or menu) lands on the completion page with the
        // missing-permission warning still shown; a relaunch with a complete pet does not auto-open it.
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
        wizard.monitoringDidObserveReaction()
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

        // A delivered key confirms it from the completion page too.
        state.observedReaction = true
        wizard.monitoringDidObserveReaction()
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

    /// Two rapid clicks on the sample shortcut must start one commit, not two writes.
    @Test func rapidSampleRequestsCommitOnce() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(
            state: state,
            demoURL: Fixture.sheetURL(),
            confirmResult: true
        )
        defer { wizard.close() }

        let first = wizard.trySamplePet()
        let second = wizard.trySamplePet()
        _ = await first.value
        _ = await second.value

        #expect(state.confirmCount == 1)
        #expect(wizard.didUseSamplePet)
        #expect(wizard.hasImage)
    }

    /// The user's file must win. While their import is suspended before its commit, a sample click
    /// must not queue a commit behind it and replace the pet they asked for.
    @Test func sampleIsIgnoredWhileAUserImportIsStillCommitting() async throws {
        let state = Fixture.State()
        let (started, signal) = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<PetImageSet?, Never>?
        let wizard = try Fixture.makeWizard(
            state: state,
            demoURL: Fixture.sheetURL(),
            preview: { _ in
                await withCheckedContinuation { continuation in
                    pending = continuation
                    signal.yield()
                }
            },
            confirmResult: true
        )
        defer { wizard.close(); signal.finish() }
        let userImages = try Fixture.sheetImages()

        let userImport = wizard.importImage(from: URL(fileURLWithPath: "/user-pet.png"))
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        #expect(wizard.pendingImportCount == 1)
        #expect(!wizard.canTrySample)

        // Clicking the sample now must start nothing.
        await wizard.trySamplePet().value
        #expect(state.confirmCount == 0)
        #expect(!wizard.didUseSamplePet)

        // The user's file finally commits, and the page still shows their pet.
        pending?.resume(returning: userImages)
        await userImport.value
        #expect(wizard.pendingImportCount == 0)
        #expect(wizard.hasImage)
        #expect(wizard.importedFileName == "user-pet.png")
        #expect(!wizard.didUseSamplePet)
        #expect(wizard.currentPetImages()[.idle].first === userImages[.idle].first)

        // A later sample click is refused too: a pet is already stored.
        await wizard.trySamplePet().value
        #expect(wizard.currentPetImages()[.idle].first === userImages[.idle].first)
        #expect(state.confirmCount == 1)
    }

    /// A failed import must release the shortcut, so the sample is still a way to a visible pet.
    @Test func aFailedImportReleasesTheSampleShortcut() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(
            state: state,
            demoURL: Fixture.sheetURL(),
            previewResult: nil
        )
        defer { wizard.close() }

        await wizard.importImage(from: URL(fileURLWithPath: "/unreadable.png")).value

        #expect(wizard.didFailImport)
        #expect(!wizard.hasImage)
        #expect(wizard.pendingImportCount == 0)
        #expect(wizard.canTrySample)
        #expect(state.confirmCount == 0)
    }
}
