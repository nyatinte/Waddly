import AppKit
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
    /// refuse the sample once the user's file has landed.
    @Test func aReopenedWizardCannotSampleOverAUserImportStillCommitting() async throws {
        let state = Fixture.State()
        let userImages = try Fixture.sheetImages()
        let (aStarted, aSignal) = AsyncStream<Void>.makeStream()
        let (bStarted, bSignal) = AsyncStream<Void>.makeStream()
        var aGate: CheckedContinuation<Void, Never>?
        var bGate: CheckedContinuation<Void, Never>?
        defer { aSignal.finish(); bSignal.finish() }

        // Mirrors the app's serialized write: a user file always wins, a sample is refused once stored.
        let write: @MainActor (PetImageSet, PetImageCommitSource) async -> Bool = { images, source in
            guard AppDelegate.shouldCommitPetImages(source: source, petIsStored: state.images.isComplete)
            else { return false }
            state.images = images
            return true
        }

        let first = try Fixture.makeWizard(
            state: state,
            demoURL: Fixture.sheetURL(),
            previewResult: userImages,
            confirm: { images, source in
                aSignal.yield()
                await withCheckedContinuation { aGate = $0 }
                return await write(images, source)
            }
        )
        let userImport = first.importImage(from: URL(fileURLWithPath: "/user-pet.png"))
        var aIterator = aStarted.makeAsyncIterator()
        _ = await aIterator.next()
        // The user closes the guide while their import is still waiting to be written.
        first.close()

        // The reopened guide starts with an empty counter, so the shortcut looks available.
        let second = try Fixture.makeWizard(
            state: state,
            demoURL: Fixture.sheetURL(),
            confirm: { images, source in
                bSignal.yield()
                await withCheckedContinuation { bGate = $0 }
                return await write(images, source)
            }
        )
        defer { second.close() }
        #expect(second.canTrySample)

        let sample = second.trySamplePet()
        var bIterator = bStarted.makeAsyncIterator()
        _ = await bIterator.next()

        // The user's file lands first; the sample's queued write then sees the stored pet.
        aGate?.resume()
        await userImport.value
        #expect(state.images[.idle].first === userImages[.idle].first)

        bGate?.resume()
        await sample.value
        #expect(state.images[.idle].first === userImages[.idle].first)
        #expect(!second.didUseSamplePet)
        #expect(!second.didRegisterPet)
        #expect(second.importedFileName == nil)
    }
}
