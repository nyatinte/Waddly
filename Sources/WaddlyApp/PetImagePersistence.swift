import AppKit
import WaddlyCore

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

    func addImages(_ urls: [URL], to category: PetImageCategory) {
        Task { [weak self] in
            guard let self else { return }
            switch await imageStore.addImages(urls, to: category) {
            case .blocked:
                await showImageLoadError()
            case let .failed(error):
                await showImageSaveError(error)
            case let .added(skipped) where skipped > 0:
                await showAlert(.imagesSkippedTitle, .imagesSkippedMessage)
            case .added, .aborted:
                break
            case .skippedAll:
                await showAlert(.imagesErrorTitle, .imagesErrorMessage)
            }
        }
    }

    @discardableResult
    func removeImage(at index: Int, from category: PetImageCategory) -> Task<Void, Never>? {
        imageStore.removeImage(at: index, from: category) { [weak self] error in
            await self?.showImageSaveError(error)
        }
    }

    @discardableResult
    func moveImage(from source: Int, to destination: Int, in category: PetImageCategory) -> Task<Void, Never>? {
        imageStore.moveImage(from: source, to: destination, in: category) { [weak self] error in
            await self?.showImageSaveError(error)
        }
    }
}
