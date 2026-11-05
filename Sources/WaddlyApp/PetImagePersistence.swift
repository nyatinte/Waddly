import AppKit
import WaddlyCore

enum PetImageCommitSource {
    case userFile
    case sample
}

extension AppDelegate {
    /// Serialize complete image transactions, including the manifest commit (run on a worker).
    ///
    /// Thin forwarder to the store's queue, which is the exclusive-access guarantee
    /// `PetImageStorage` requires across the stage → commit → reconcile transaction.
    func queueImageUpdate(_ operation: @escaping @MainActor () async -> Bool) async -> Bool {
        await imageStore.queue(operation)
    }

    /// Persist a frame set with the on-disk manifest as the source of truth.
    /// Transaction primitive: call from an already-queued image operation, not concurrently.
    func persistPetImages(
        _ updated: PetImageSet,
        encodedImages: [ObjectIdentifier: Data] = [:],
        resetActivity: Bool = false,
        cleanup: @escaping @Sendable (PetImageStorage) async -> Void = { storage in
            await Task.detached { _ = try? storage.reconcileFiles() }.value
        }
    ) async throws {
        try await imageStore.persist(
            updated,
            encodedImages: encodedImages,
            resetActivity: resetActivity,
            cleanup: cleanup
        )
    }

    @discardableResult
    func removeImage(at index: Int, from category: PetImageCategory) -> Task<Void, Never>? {
        imageStore.removeImage(at: index, from: category) { [weak self] error in
            await self?.showImageSaveError(error)
        }
    }

    /// Check the sample guard inside the store queue, after any earlier commits have finished.
    func commitCharacterImages(
        _ images: PetImageSet,
        source: PetImageCommitSource = .userFile
    ) async -> CharacterCommitOutcome {
        switch await imageStore.confirmPetImage(images, accepting: {
            Self.shouldCommitPetImages(source: source, petIsStored: self.hasCompletePetImageSet)
        }) {
        case .confirmed: .committed
        case .failed: .failed
        case .aborted: .rejected
        }
    }

    @discardableResult
    func moveImage(from source: Int, to destination: Int, in category: PetImageCategory) -> Task<Void, Never>? {
        imageStore.moveImage(from: source, to: destination, in: category) { [weak self] error in
            await self?.showImageSaveError(error)
        }
    }
}
