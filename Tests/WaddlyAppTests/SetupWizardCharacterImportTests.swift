import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// The shared import screen inside the Setup Pet step: the shell keeps progress and Continue, while a
/// failed save stays on the step with an inline retry instead of a separate alert.
@Suite(.serialized) @MainActor struct SetupWizardCharacterImportTests {
    @Test func thePetStepHostsTheSharedScreenAndKeepsProgress() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(state: state, demoURL: Fixture.sheetURL())
        defer { wizard.close() }
        let recordedBefore = wizard.currentStep

        wizard.beginCharacterImport()
        #expect(wizard.isComposingCharacter)

        try await wizard.characterImportModel.stageFiles(at: [Fixture.sheetURL()])
        #expect(wizard.characterImportModel.stagedFrames?.isComplete == true)

        await wizard.commitCharacterImportAndContinue().value

        #expect(!wizard.isComposingCharacter)
        #expect(wizard.didRegisterPet)
        #expect(try wizard.importedFileName == (Fixture.sheetURL()).lastPathComponent)
        #expect(wizard.currentStep == .monitoring)
        #expect(recordedBefore == .pet)
    }

    @Test func duplicateSetupApplyDoesNotAdvanceBeforeTheSuspendedCommitFails() async throws {
        let state = Fixture.State()
        let gate = CharacterImportCommitGate()
        let wizard = try Fixture.makeWizard(state: state, commitCharacter: { _ in
            state.commitCharacterCount += 1
            return await gate.commit()
        })
        defer { wizard.close() }
        wizard.beginCharacterImport()
        try await wizard.characterImportModel.stageFiles(at: [Fixture.sheetURL()])

        let first = wizard.commitCharacterImportAndContinue()
        #expect(await gate.waitUntilEntered())
        await wizard.commitCharacterImportAndContinue().value
        wizard.cancelCharacterImport()
        #expect(try !wizard.windowShouldClose(#require(wizard.window)))
        #expect(wizard.currentStep == .pet)
        #expect(wizard.isComposingCharacter)
        #expect(state.commitCharacterCount == 1)
        #expect(gate.commitCount == 1)

        gate.resume(with: .failed)
        await first.value
        #expect(wizard.currentStep == .pet)
        #expect(wizard.isComposingCharacter)
        #expect(wizard.characterImportModel.commitFailed)
        #expect(state.commitCharacterCount == 1)
        #expect(gate.commitCount == 1)
    }

    /// A failed persistence keeps the staged draft and the step: no advance, no committed pet, and the
    /// shared screen's inline retry is what the user sees.
    @Test func aFailedSetupCommitStaysOnTheStepWithAnInlineRetry() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(state: state, commitCharacterOutcome: .failed)
        defer { wizard.close() }
        wizard.beginCharacterImport()
        try await wizard.characterImportModel.stageFiles(at: [Fixture.sheetURL()])

        await wizard.commitCharacterImportAndContinue().value

        #expect(wizard.characterImportModel.commitFailed)
        #expect(wizard.characterImportModel.stagedFrames?.isComplete == true)
        #expect(wizard.characterImportModel.canApply)
        #expect(wizard.currentStep == .pet)
        #expect(wizard.isComposingCharacter)
        #expect(!wizard.hasImage)
    }

    /// Leaving an untouched shared screen returns to the method list immediately and never commits.
    @Test func closingTheWizardConfirmsDiscardOfADirtySharedDraft() async throws {
        let state = Fixture.State()
        let alertState = AlertResponseState()
        var presenter = WindowPresenter.invisible
        presenter.presentAlert = { _, _, completion in
            alertState.presentationCount += 1
            completion(alertState.response)
        }
        let wizard = try Fixture.makeWizard(state: state, presenter: presenter)
        defer {
            wizard.characterImportModel.discard()
            wizard.close()
        }
        wizard.beginCharacterImport()
        try await wizard.characterImportModel.stageFiles(at: [Fixture.sheetURL()])
        let window = try #require(wizard.window)
        wizard.showWindow(nil)
        #expect(wizard.characterImportModel.isDirty)

        #expect(!wizard.windowShouldClose(window))
        #expect(alertState.presentationCount == 1)
        #expect(window.isVisible)
        #expect(wizard.characterImportModel.isDirty)
        #expect(state.commitCharacterCount == 0)
        #expect(wizard.currentStep == .pet)

        alertState.response = .alertFirstButtonReturn
        #expect(!wizard.windowShouldClose(window))
        #expect(alertState.presentationCount == 2)
        #expect(!window.isVisible)
        #expect(state.closed)
        #expect(state.commitCharacterCount == 0)
        #expect(wizard.currentStep == .pet)
    }

    @Test func anUntouchedWizardCanCloseWithoutConfirmation() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        #expect(try wizard.windowShouldClose(#require(wizard.window)))
    }

    @Test func cancellingAnUntouchedSharedScreenLeavesWithoutPrompting() throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(state: state)
        defer { wizard.close() }
        wizard.beginCharacterImport()
        #expect(wizard.isComposingCharacter)

        wizard.cancelCharacterImport()

        #expect(!wizard.isComposingCharacter)
        #expect(state.commitCharacterCount == 0)
    }

    /// A staged-but-uncommitted draft is discarded without writing anything.
    @Test func discardingAStagedDraftLeavesTheCommittedPetUntouched() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(state: state)
        defer { wizard.close() }
        wizard.beginCharacterImport()
        try await wizard.characterImportModel.stageFiles(at: [Fixture.sheetURL()])
        #expect(wizard.characterImportModel.isDirty)

        wizard.characterImportModel.discard()

        #expect(wizard.characterImportModel.stagedFrames == nil)
        #expect(state.commitCharacterCount == 0)
        #expect(!wizard.hasImage)
    }

    @Test func theDropZoneHighlightFollowsDragEligibility() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        wizard.beginCharacterImport()
        #expect(!wizard.characterImportModel.isDropTargeted)
        wizard.characterImportModel.setDropTargeted(true)
        #expect(wizard.characterImportModel.isDropTargeted)
        wizard.characterImportModel.discard()
        #expect(!wizard.characterImportModel.isDropTargeted)
    }

    /// The window-wide drop stages while composing and keeps the direct import otherwise; the drop
    /// itself never commits a staged draft, so only Continue can write one.
    @Test func windowWideDropStagesWhileComposingAndImportsOtherwise() async throws {
        let url = try Fixture.sheetURL()

        let legacyState = Fixture.State()
        let legacy = try Fixture.makeWizard(
            state: legacyState,
            previewResult: Fixture.sheetImages(),
            confirmResult: true
        )
        defer { legacy.close() }
        legacy.handleWindowDrop([url])
        #expect(await waitUntil { legacyState.confirmCount == 1 })

        let composingState = Fixture.State()
        let composing = try Fixture.makeWizard(state: composingState)
        defer { composing.close() }
        composing.beginCharacterImport()
        composing.handleWindowDrop([url])
        #expect(await waitUntil { composing.characterImportModel.stagedFrames?.isComplete == true })
        #expect(composing.characterImportModel.canApply)
        #expect(composingState.commitCharacterCount == 0)
        #expect(!composing.hasImage)

        // A multi-file window-wide drop is refused and still writes nothing.
        composing.handleWindowDrop([url, url])
        #expect(await waitUntil { composing.characterImportModel.failure == .multipleFiles })
        #expect(composingState.commitCharacterCount == 0)
    }
}

@MainActor
private final class AlertResponseState {
    var response: NSApplication.ModalResponse = .alertSecondButtonReturn
    var presentationCount = 0
}

private extension SetupWizardCharacterImportTests {
    /// Polls a main-actor condition, used where an action starts an unstructured task.
    func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0 ..< 300 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
