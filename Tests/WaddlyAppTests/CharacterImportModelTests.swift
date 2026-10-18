import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// The shared acquisition → inspect → commit state machine: staging stays a draft, invalid input
/// never touches the committed pet, a failed save is retryable, and stale acquisitions are dropped.
@Suite(.serialized) @MainActor struct CharacterImportModelTests {
    @Test func stagingAValidSheetReportsGeometryWithoutCommitting() async throws {
        let sheetURL = try SetupWizardFixture.sheetURL()
        var committed: PetImageSet?
        let model = makeModel(current: PetImageSet(), commit: { committed = $0; return .committed })

        await model.stageFiles(at: [sheetURL])

        #expect(model.stagedFrames?.isComplete == true)
        #expect(model.sourceName == sheetURL.lastPathComponent)
        #expect(model.sourceDimension != nil)
        #expect(model.cellSize != nil)
        #expect(model.isDirty)
        #expect(committed == nil)
    }

    @Test func anInvalidImportKeepsThePreviousStagedCandidate() async throws {
        let sheetURL = try SetupWizardFixture.sheetURL()
        let model = makeModel(current: PetImageSet(), commit: { _ in .committed })
        await model.stageFiles(at: [sheetURL])
        let staged = try #require(model.stagedFrames)

        await model.stageFiles(at: [URL(fileURLWithPath: "/tmp/waddly-missing-sheet.png")])

        #expect(model.failure == .sheet(.unreadable))
        #expect(model.stagedFrames?[.idle].first === staged[.idle].first)
    }

    @Test func aMultiFileSheetDropIsRejected() async throws {
        let sheetURL = try SetupWizardFixture.sheetURL()
        let model = makeModel(current: PetImageSet(), commit: { _ in .committed })

        await model.stageFiles(at: [sheetURL, sheetURL])

        #expect(model.failure == .multipleFiles)
        #expect(model.stagedFrames == nil)
    }

    @Test func anEmptyClipboardGivesAnInformationalFailure() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WaddlyTests.model.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let model = makeModel(current: PetImageSet(), commit: { _ in .committed })

        await model.stageClipboard(from: pasteboard)

        #expect(model.failure == .noClipboardImage)
        #expect(model.stagedFrames == nil)
    }

    @Test func aFailedSaveKeepsTheDraftForRetry() async throws {
        let model = makeModel(current: PetImageSet(), commit: { _ in .failed })
        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])

        await model.apply()

        #expect(model.commitFailed)
        #expect(model.stagedFrames?.isComplete == true)
        #expect(model.canApply)
    }

    @Test func aSuccessfulApplyRebasesTheBaseline() async throws {
        var stored = PetImageSet()
        let model = makeModel(current: PetImageSet(), commit: { stored = $0; return .committed })
        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])
        #expect(model.isDirty)

        await model.apply()

        #expect(!model.commitFailed)
        #expect(!model.isDirty)
        #expect(stored.isComplete)
    }

    @Test func discardLeavesTheCommittedPetUntouched() async throws {
        let committed = try SetupWizardFixture.sheetImages()
        let model = makeModel(current: committed, commit: { _ in .committed })
        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])
        #expect(model.isDirty)

        model.discard()

        #expect(model.stagedFrames == nil)
        #expect(!model.isDirty)
    }

    @Test func aStaleAcquisitionCannotOverwriteNewerState() async throws {
        let model = makeModel(current: PetImageSet(), commit: { _ in .committed })
        let sheetURL = try SetupWizardFixture.sheetURL()

        let stalled = Task { await model.stageFiles(at: [sheetURL]) }
        // Let the acquisition start reading, then invalidate it before it can publish.
        await Task.yield()
        model.discard()
        await stalled.value

        #expect(model.stagedFrames == nil)
        #expect(!model.isReading)
    }
}

@MainActor
private func makeModel(
    current: PetImageSet,
    commit: @escaping (PetImageSet) async -> CharacterCommitOutcome
) -> CharacterImportModel {
    CharacterImportModel(currentImages: { current }, commit: commit)
}
