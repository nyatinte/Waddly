import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct SetupWizardSampleGuardTests {
    @Test func stagedSampleCannotReplaceAPetSavedByAnotherWindow() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(state: state, demoURL: Fixture.sheetURL(), confirmResult: true)
        defer { wizard.close() }
        let sample = try #require(wizard.demoImages)
        wizard.characterImportModel.stageSample(sample, name: "Sample")

        let savedPet = try Fixture.sheetImages()
        state.images = savedPet
        await wizard.commitCharacterImportAndContinue().value

        #expect(state.confirmCount == 0)
        #expect(state.images[.idle].first === savedPet[.idle].first)
        #expect(wizard.currentStep == .pet)
        #expect(wizard.characterImportModel.isSampleCandidate)
    }
}
