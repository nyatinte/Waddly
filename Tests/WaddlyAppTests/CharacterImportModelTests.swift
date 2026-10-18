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

    @Test func staleEditorAddCannotAppendToReplacementDraft() async throws {
        let sheetURL = try SetupWizardFixture.sheetURL()
        let original = await CharacterSheetLoader.load(from: sheetURL)
        let replacement = await CharacterSheetLoader.load(from: sheetURL)
        let replacementURL = URL(fileURLWithPath: "/tmp/waddly-replacement.png")
        let editorURL = URL(fileURLWithPath: "/tmp/waddly-editor-frame.png")
        let addedFrames = try [#require(SetupWizardFixture.sheetImages()[.idle].first)]
        let gate = FrameDecodeGate(images: addedFrames)
        let model = CharacterImportModel(
            currentImages: { PetImageSet() },
            commit: { _ in .committed },
            loadSheet: { url in url == replacementURL ? replacement : original },
            decodeFrames: { _ in await gate.decode() }
        )
        await model.stageFiles(at: [sheetURL])
        let add = Task { await model.addFrames([editorURL], to: .idle) }
        #expect(await gate.waitUntilStarted())

        await model.stageFiles(at: [replacementURL])
        let replacementFrames = try #require(model.stagedFrames)
        gate.release()
        await add.value

        #expect(try CharacterImportModel.sameFrames(#require(model.stagedFrames), replacementFrames))
        #expect(model.stagedFrames?[.idle].count == replacementFrames[.idle].count)
    }

    @Test func staleEditorAddCannotRestoreDiscardedDraft() async throws {
        let sheetURL = try SetupWizardFixture.sheetURL()
        let frames = try #require(SetupWizardFixture.sheetImages()[.idle].first)
        let gate = FrameDecodeGate(images: [frames])
        let model = CharacterImportModel(
            currentImages: { PetImageSet() },
            commit: { _ in .committed },
            decodeFrames: { _ in await gate.decode() }
        )
        await model.stageFiles(at: [sheetURL])
        let add = Task { await model.addFrames([sheetURL], to: .idle) }
        #expect(await gate.waitUntilStarted())

        model.discard()
        gate.release()
        await add.value

        #expect(model.stagedFrames == nil)
        #expect(!model.isDirty)
    }

    @Test func anInFlightEditorAddCannotMutateDraftDuringOrAfterApply() async throws {
        let sheetURL = try SetupWizardFixture.sheetURL()
        let frame = try #require(SetupWizardFixture.sheetImages()[.idle].first)
        let decoder = FrameDecodeGate(images: [frame])
        let commit = CharacterCommitOutcomeGate()
        let model = CharacterImportModel(
            currentImages: { PetImageSet() },
            commit: { _ in await commit.commit() },
            decodeFrames: { _ in await decoder.decode() }
        )
        await model.stageFiles(at: [sheetURL])
        let original = try #require(model.stagedFrames)
        let add = Task { await model.addFrames([sheetURL], to: .idle) }
        #expect(await decoder.waitUntilStarted())
        let apply = Task { await model.apply() }
        #expect(await commit.waitUntilStarted())

        model.removeFrame(at: 0, from: .idle)
        model.moveFrame(from: 0, to: 1, in: .idle)
        commit.release(.committed)
        #expect(await apply.value)
        decoder.release()
        await add.value

        #expect(try CharacterImportModel.sameFrames(#require(model.stagedFrames), original))
        #expect(!model.isDirty)
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

        #expect(model.stagedFrames == nil)
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
private final class SheetLoadGate {
    private let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private var continuation: CheckedContinuation<CharacterSheetLoadOutcome, Never>?
    private let outcome: CharacterSheetLoadOutcome

    init(outcome: CharacterSheetLoadOutcome) {
        self.outcome = outcome
        let (started, signal) = AsyncStream<Void>.makeStream()
        self.started = started
        self.signal = signal
    }

    func load() async -> CharacterSheetLoadOutcome {
        signal.yield(())
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async -> Bool {
        await waitForSignal(started)
    }

    func release() {
        guard let continuation else {
            Issue.record("sheet load gate released before it started")
            return
        }
        self.continuation = nil
        continuation.resume(returning: outcome)
    }
}

@MainActor
private final class CharacterCommitOutcomeGate {
    private let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private var continuation: CheckedContinuation<CharacterCommitOutcome, Never>?

    init() {
        let (started, signal) = AsyncStream<Void>.makeStream()
        self.started = started
        self.signal = signal
    }

    func commit() async -> CharacterCommitOutcome {
        signal.yield(())
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async -> Bool {
        await waitForSignal(started)
    }

    func release(_ outcome: CharacterCommitOutcome) {
        guard let continuation else {
            Issue.record("character commit gate released before it started")
            return
        }
        self.continuation = nil
        continuation.resume(returning: outcome)
    }
}

@MainActor
private final class FrameDecodeGate {
    private let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private var continuation: CheckedContinuation<[NSImage], Never>?
    private let images: [NSImage]

    init(images: [NSImage]) {
        self.images = images
        let (started, signal) = AsyncStream<Void>.makeStream()
        self.started = started
        self.signal = signal
    }

    func decode() async -> [NSImage] {
        signal.yield(())
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async -> Bool {
        await waitForSignal(started)
    }

    func release() {
        guard let continuation else {
            Issue.record("frame decode gate released before it started")
            return
        }
        self.continuation = nil
        continuation.resume(returning: images)
    }
}

@MainActor
private func waitForSignal(_ started: AsyncStream<Void>) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            var iterator = started.makeAsyncIterator()
            return await iterator.next() != nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(2))
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}

@MainActor
private func makeModel(
    current: PetImageSet,
    commit: @escaping (PetImageSet) async -> CharacterCommitOutcome
) -> CharacterImportModel {
    CharacterImportModel(currentImages: { current }, commit: commit)
}
