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

    @Test func aFailedReplacementOfALoadedPetIsApplicableButNotAFreshImport() async throws {
        let committed = try SetupWizardFixture.sheetImages()
        let model = makeModel(current: committed, commit: { _ in .committed })
        model.reload()

        await model.stageFiles(at: [URL(fileURLWithPath: "/tmp/waddly-\(UUID().uuidString).png")])

        #expect(model.failure == .sheet(.unreadable))
        #expect(model.canApply)
        #expect(!model.isDirty)
        #expect(try CharacterImportModel.sameFrames(#require(model.stagedFrames), committed))
    }

    @Test func aMultiFileSheetDropIsRejected() async throws {
        let sheetURL = try SetupWizardFixture.sheetURL()
        let model = makeModel(current: PetImageSet(), commit: { _ in .committed })

        await model.stageFiles(at: [sheetURL, sheetURL])

        #expect(model.failure == .multipleFiles)
        #expect(model.stagedFrames == nil)
    }

    @Test func newerMultipleFileDropInvalidatesSuspendedReadAndPreservesDraft() async throws {
        let sheetURL = try SetupWizardFixture.sheetURL()
        let pendingURL = URL(fileURLWithPath: "/tmp/waddly-pending-sheet.png")
        let pendingOutcome = await CharacterSheetLoader.load(from: sheetURL)
        let gate = SheetLoadGate(outcome: pendingOutcome)
        let model = CharacterImportModel(
            currentImages: { PetImageSet() },
            commit: { _ in .committed },
            loadSheet: { url in
                if url == pendingURL {
                    return await gate.load()
                }
                return await CharacterSheetLoader.load(from: url)
            }
        )
        await model.stageFiles(at: [sheetURL])
        let staged = try #require(model.stagedFrames)

        let pendingRead = Task { await model.stageFiles(at: [pendingURL]) }
        #expect(await gate.waitUntilStarted())
        #expect(!model.canApply)
        await model.stageDroppedFiles(at: [sheetURL, sheetURL])
        #expect(model.canApply)
        #expect(model.failure == .multipleFiles)
        #expect(!model.isReading)
        #expect(try CharacterImportModel.sameFrames(#require(model.stagedFrames), staged))

        gate.release()
        await pendingRead.value

        #expect(model.failure == .multipleFiles)
        #expect(!model.isReading)
        #expect(try CharacterImportModel.sameFrames(#require(model.stagedFrames), staged))
    }

    @Test func sharedDropRoutesUnsupportedAndMixedFilesToInlineValidation() async throws {
        let model = makeModel(current: PetImageSet(), commit: { _ in .committed })
        let jpg = URL(fileURLWithPath: "/tmp/waddly-unsupported.jpg")
        let png = try SetupWizardFixture.sheetURL()

        await model.stageDroppedFiles(at: [jpg])
        #expect(model.failure == .sheet(.notPNG))

        await model.stageDroppedFiles(at: [png, jpg])
        #expect(model.failure == .multipleFiles)
        #expect(!model.isReading)
    }

    @Test func releasingEachGateBeforeStartReturnsTheLatchedResult() async {
        let sheetOutcome = CharacterSheetLoadOutcome.empty
        let sheetGate = SheetLoadGate(outcome: sheetOutcome)
        sheetGate.release()
        guard case .empty = await sheetGate.load() else {
            Issue.record("sheet gate did not return its latched result")
            return
        }

        let commitGate = CharacterCommitOutcomeGate()
        commitGate.release(.rejected)
        #expect(await commitGate.commit() == .rejected)
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

        #expect(await !(model.apply()))

        #expect(model.commitFailed)
        #expect(model.stagedFrames?.isComplete == true)
        #expect(model.canApply)
    }

    @Test func aSuccessfulApplyRebasesTheBaseline() async throws {
        var stored = PetImageSet()
        let model = makeModel(current: PetImageSet(), commit: { stored = $0; return .committed })
        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])
        #expect(model.isDirty)

        #expect(await model.apply())

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

        let discarded = try #require(model.stagedFrames)
        #expect(CharacterImportModel.sameFrames(discarded, committed))
        #expect(!model.isDirty)
    }

    /// Availability tracks the pasteboard's types: nothing, PNG pixels, and a bitmap-only (TIFF)
    /// clipboard each classify correctly.
    @Test func clipboardAvailabilityTracksThePasteboardContents() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WaddlyTests.model.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let model = makeModel(current: PetImageSet(), commit: { _ in .committed })
        model.refreshClipboardAvailability(from: pasteboard)
        #expect(!model.clipboardHasImage)

        let frame = try #require(SetupWizardFixture.sheetImages()[.idle].first)
        try pasteboard.setData(#require(PetSpriteSheetImporter.pngData(for: frame)), forType: .png)
        model.refreshClipboardAvailability(from: pasteboard)
        #expect(model.clipboardHasImage)

        pasteboard.clearContents()
        try pasteboard.setData(#require(frame.tiffRepresentation), forType: .tiff)
        model.refreshClipboardAvailability(from: pasteboard)
        #expect(model.clipboardHasImage)
    }

    @Test func aStaleAcquisitionCannotOverwriteNewerState() async throws {
        let model = makeModel(current: PetImageSet(), commit: { _ in .committed })
        let sheetURL = try SetupWizardFixture.sheetURL()

        let stalled = Task { await model.stageFiles(at: [sheetURL]) }
        // Handshake on the observable reading state instead of a single yield: only once the
        // acquisition has actually begun can invalidating it be the stale case under test.
        var beganReading = false
        for _ in 0 ..< 500 {
            if model.isReading {
                beganReading = true
                break
            }
            await Task.yield()
        }
        #expect(beganReading)
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
