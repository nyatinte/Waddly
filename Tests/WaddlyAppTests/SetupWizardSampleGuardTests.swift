import AppKit
import Combine
import Testing
@testable import WaddlyApp
import WaddlyCore

/// The sample shortcut must never replace a pet the user asked for, including across a close and
/// reopen. Kept apart from `SetupWizardJourneyTests` so each suite stays readable.
@Suite(.serialized) @MainActor struct SetupWizardSampleGuardTests {
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

    /// A reopened window has a fresh counter, so the shortcut looks available again while the
    /// previous window's import is still waiting to be written. The serialized commit must still
    /// refuse the sample once the user's file has landed, and the refusal must repaint the page.
    @Test func aReopenedWizardCannotSampleOverAUserImportStillCommitting() async throws {
        let state = Fixture.State()
        let userImages = try Fixture.sheetImages()
        let firstWrite = CommitmentGate()
        let secondWrite = CommitmentGate()
        defer { firstWrite.finish(); secondWrite.finish() }

        let first = try gatedWizard(state: state, previewResult: userImages, gate: firstWrite)
        let userImport = first.importImage(from: URL(fileURLWithPath: "/user-pet.png"))
        await firstWrite.waitUntilStarted()
        // The user closes the guide while their import is still waiting to be written.
        first.close()

        // The reopened guide starts with an empty counter, so the shortcut looks available.
        let second = try gatedWizard(state: state, previewResult: nil, gate: secondWrite)
        defer { second.close() }
        #expect(second.canTrySample)

        // A refusal can still change the page, so watch the signal the controller already publishes.
        var repaints = 0
        let repaintObserver = second.objectWillChange.sink { _ in repaints += 1 }
        defer { repaintObserver.cancel() }

        let sample = second.trySamplePet()
        await secondWrite.waitUntilStarted()

        // The user's file lands first; the sample's queued write then sees the stored pet.
        firstWrite.release()
        await userImport.value
        #expect(state.images[.idle].first === userImages[.idle].first)

        let repaintsBeforeRefusal = repaints
        secondWrite.release()
        await sample.value
        #expect(state.images[.idle].first === userImages[.idle].first)
        #expect(!second.didUseSamplePet)
        #expect(!second.didRegisterPet)
        #expect(second.importedFileName == nil)

        // The refused sample repaints: the shortcut is gone and the stored pet replaced the option
        // list, so the footer's Next is enabled from a fresh evaluation.
        #expect(repaints > repaintsBeforeRefusal)
        #expect(!second.canTrySample)
        #expect(second.hasImage)
        #expect(second.previewPane.hasPet)
    }

    /// A wizard whose commits are held open until `gate.release()`, modelling a queued write.
    private func gatedWizard(
        state: Fixture.State,
        previewResult: PetImageSet?,
        gate: CommitmentGate
    ) throws -> SetupWizardController {
        try Fixture.makeWizard(
            state: state,
            demoURL: Fixture.sheetURL(),
            previewResult: previewResult,
            confirm: { images, source in await gate.commit(images, source, to: state) }
        )
    }
}

/// One queued pet commit the test can hold open and release, mirroring the app's serial queue.
@MainActor private final class CommitmentGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private let signal: AsyncStream<Void>.Continuation
    private let started: AsyncStream<Void>

    init() {
        (started, signal) = AsyncStream<Void>.makeStream()
    }

    /// Signals that the commit is queued, then waits for `release` before applying the app's rule.
    func commit(_ images: PetImageSet, _ source: PetImageCommitSource, to state: Fixture.State) async -> Bool {
        signal.yield()
        await withCheckedContinuation { continuation = $0 }
        guard AppDelegate.shouldCommitPetImages(source: source, petIsStored: state.images.isComplete) else {
            return false
        }
        state.images = images
        return true
    }

    func waitUntilStarted() async {
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    func finish() {
        signal.finish()
    }
}
