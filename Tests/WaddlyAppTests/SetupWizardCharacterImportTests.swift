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
}
