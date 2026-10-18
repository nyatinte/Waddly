import AppKit
import Testing
@testable import WaddlyCore

/// The store owns image state and the serialized save queue, so these tests drive it directly with
/// an in-memory legacy mirror and a recorded publish callback instead of an `AppDelegate`. Restore
/// cases live in `PetImageStoreRestoreTests`.
@Suite(.serialized) @MainActor struct PetImageStoreTests {
    @Test func movingAnElementPreservesTheRequestedOrder() {
        let elements = ["first", "second", "third"]

        #expect(PetImageStore.moving(elements, from: 0, to: 2) == ["second", "third", "first"])
        #expect(PetImageStore.moving(elements, from: 2, to: 0) == ["third", "first", "second"])
        #expect(PetImageStore.moving(["only"], from: 1, to: 0) == nil)
    }

    @Test func imageEditsStaySerializedAcrossWorkerSuspensions() async {
        let store = makeImageStore()
        defer { closeImageStore(store) }
        let (started, startSignal) = AsyncStream<Void>.makeStream()
        let (release, releaseSignal) = AsyncStream<Void>.makeStream()
        var events: [Int] = []
        let first = Task {
            await store.queue {
                events.append(1)
                startSignal.yield()
                for await _ in release {
                    break
                }
                events.append(2)
                return true
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        let second = Task {
            await store.queue {
                events.append(3)
                return true
            }
        }
        await Task.yield()
        #expect(events == [1])
        releaseSignal.yield()
        #expect(await first.value)
        #expect(await second.value)
        #expect(events == [1, 2, 3])
        startSignal.finish()
        releaseSignal.finish()

        store.beginShutdown()
        let accepted = await store.queue {
            events.append(4)
            return true
        }
        #expect(!accepted)
        #expect(events == [1, 2, 3])
    }

    /// A shutdown between staging and commit removes only the files this save created, keeping the
    /// committed manifest and images.
    @Test func shutdownBetweenStageAndCommitRollsBackStagedFiles() async throws {
        let mirror = StoreLegacyMirror()
        let store = makeImageStore(mirror: mirror)
        defer { closeImageStore(store) }
        let images = try storeExampleImages()
        try await store.persist(images)
        let storage = try PetImageStorage(directory: #require(store.directory))
        let committed = try storeCommittedManifest(in: storage)
        let committedFrames = try storeFrameData(in: storage.directory)
        let committedThumbnails = store.thumbnails

        store.beginShutdown()
        do {
            try await store.persist(PetImageSet([.idle: [store.images[.idle][0]]]))
            Issue.record("expected the shutdown to reject the commit")
        } catch {
            #expect(error is CancellationError)
        }

        #expect(try storage.readManifest() == committed)
        #expect(try storeFrameData(in: storage.directory) == committedFrames)
        #expect(store.files == committed)
        #expect(store.images[.idle].count == 2)
        #expect(store.thumbnails.count == committedThumbnails.count)
        let rejected = await store.addImages([URL(fileURLWithPath: "/nonexistent.png")], to: .idle)
        guard case .aborted = rejected else {
            Issue.record("expected shutdown to abort the add, got \(rejected)")
            return
        }
    }

    /// A failed commit leaves the previous manifest, images, and mirror untouched; the next save
    /// succeeds once the manifest is writable again.
    @Test func failedCommitThenSuccessKeepsStateConsistent() async throws {
        let mirror = StoreLegacyMirror()
        let store = makeImageStore(mirror: mirror)
        defer { closeImageStore(store) }
        let images = try storeExampleImages()
        try await store.persist(images)
        let storage = try PetImageStorage(directory: #require(store.directory))
        let committed = try storeCommittedManifest(in: storage)
        let committedFrames = try storeFrameData(in: storage.directory)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: storage.manifestURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: storage.manifestURL.path) }

        do {
            try await store.persist(PetImageSet([.idle: [store.images[.idle][0]]]))
            Issue.record("expected the commit to fail")
        } catch {
            #expect(error is PetImageManifestError)
        }
        #expect(try storage.readManifest() == committed)
        #expect(try storeFrameData(in: storage.directory) == committedFrames)
        #expect(store.files == committed)
        #expect(mirror.files == committed)
        #expect(store.images[.idle].count == 2)

        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: storage.manifestURL.path)
        let slimmer = PetImageSet([.idle: [store.images[.idle][0]]])
        try await store.persist(slimmer, resetActivity: true)
        #expect(store.images[.idle].count == 1)
        #expect(store.files[PetImageCategory.idle.rawValue]?.count == 1)
        #expect(mirror.files[PetImageCategory.idle.rawValue]?.count == 1)
        #expect(try storage.readManifest() == store.files)
    }

    /// A reorder queued behind another edit re-resolves its frames by identity, so it lands against
    /// the current order instead of the indices captured when the user grabbed the frame.
    @Test func staleReorderResolvesAgainstCurrentOrder() async throws {
        let store = makeImageStore()
        defer { closeImageStore(store) }
        try await store.persist(storeExampleImages())
        let typing = store.images[.typing]
        let (started, startSignal) = AsyncStream<Void>.makeStream()
        let (release, releaseSignal) = AsyncStream<Void>.makeStream()

        let removal = Task {
            await store.queue {
                startSignal.yield()
                for await _ in release {
                    break
                }
                var updated = store.images
                updated[.typing] = [typing[0], typing[2], typing[3]]
                try? await store.persist(updated)
                return true
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()

        // Captured while all four frames are still visible: move the first before the third.
        let move = store.moveImage(from: 0, to: 2, in: .typing)
        releaseSignal.yield()
        releaseSignal.finish()
        startSignal.finish()
        #expect(await removal.value)
        await move?.value

        let reordered = store.images[.typing]
        #expect(reordered.count == 3)
        #expect(reordered[0] === typing[2])
        #expect(reordered[1] === typing[0])
        #expect(reordered[2] === typing[3])
    }

    /// A reorder whose grabbed frame is already gone is a no-op rather than a wrong removal.
    @Test func staleMoveWithMissingFrameIsANoOp() async throws {
        let store = makeImageStore()
        defer { closeImageStore(store) }
        try await store.persist(storeExampleImages())
        let typing = store.images[.typing]
        let (started, startSignal) = AsyncStream<Void>.makeStream()
        let (release, releaseSignal) = AsyncStream<Void>.makeStream()

        let removal = Task {
            await store.queue {
                startSignal.yield()
                for await _ in release {
                    break
                }
                var updated = store.images
                updated[.typing] = [typing[0], typing[2], typing[3]]
                try? await store.persist(updated)
                return true
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()

        // Grabs the frame that the suspended edit is about to remove.
        let move = store.moveImage(from: 1, to: 2, in: .typing)
        releaseSignal.yield()
        releaseSignal.finish()
        startSignal.finish()
        #expect(await removal.value)
        await move?.value

        let remaining = store.images[.typing]
        #expect(remaining.count == 3)
        #expect(remaining[0] === typing[0])
        #expect(remaining[1] === typing[2])
        #expect(remaining[2] === typing[3])
    }

    /// The manifest commit, the published state, and the legacy mirror land before cleanup starts.
    @Test func commitAndPublishLandBeforeCleanup() async throws {
        let mirror = StoreLegacyMirror()
        let store = makeImageStore(mirror: mirror)
        defer { closeImageStore(store) }
        try await store.persist(storeExampleImages())
        let storage = try PetImageStorage(directory: #require(store.directory))
        let slimmer = PetImageSet([.idle: [store.images[.idle][0]]])
        let (started, startSignal) = AsyncStream<Void>.makeStream()
        let (release, releaseSignal) = AsyncStream<Void>.makeStream()
        let save = Task {
            try await store.persist(slimmer, cleanup: { _ in
                startSignal.yield()
                for await _ in release {
                    break
                }
            })
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()

        let committed = try storeCommittedManifest(in: storage)
        #expect(committed == mirror.files)
        #expect(committed.keys.sorted() == [PetImageCategory.idle.rawValue])
        #expect(committed[PetImageCategory.idle.rawValue]?.count == 1)
        #expect(store.images[.idle].count == 1)
        // Cleanup has not run yet, so the unreferenced frames are still on disk.
        #expect(try storeFrameData(in: storage.directory).count == 9)

        releaseSignal.yield()
        releaseSignal.finish()
        startSignal.finish()
        try await save.value
    }

    /// The confirmation wait of an import is inside the queue, so another edit cannot run while the
    /// sheet the user is deciding on is still open.
    @Test func importConfirmationHoldsTheQueueUntilItResolves() async throws {
        let store = makeImageStore()
        defer { closeImageStore(store) }
        let source = try storeExampleSheetURL()
        let (started, startSignal) = AsyncStream<Void>.makeStream()
        let (release, releaseSignal) = AsyncStream<Void>.makeStream()
        let importing = Task {
            await store.importPetImage(from: source) { _, _ in
                startSignal.yield()
                for await _ in release {
                    break
                }
                return true
            }
        }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()

        var ranWhileConfirming = false
        let queued = Task {
            await store.queue {
                ranWhileConfirming = true
                return true
            }
        }
        await Task.yield()
        #expect(!ranWhileConfirming)

        releaseSignal.yield()
        releaseSignal.finish()
        startSignal.finish()
        let outcome = await importing.value
        guard case .imported = outcome else {
            Issue.record("expected the confirmed import to commit, got \(outcome)")
            return
        }
        #expect(await queued.value)
        #expect(ranWhileConfirming)
        #expect(store.hasCompleteImageSet)
    }
}
