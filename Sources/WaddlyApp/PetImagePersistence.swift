import AppKit
import WaddlyCore

extension AppDelegate {
    /// Serialize complete image transactions, including their main-actor manifest commit.
    func queueImageUpdate(_ operation: @escaping @MainActor () async -> Bool) async -> Bool {
        let previous = pendingImageUpdate
        let task = Task { @MainActor in
            await previous?.value
            guard !isShuttingDown else { return false }
            return await operation()
        }
        pendingImageUpdate = Task { _ = await task.value }
        return await task.value
    }

    func persistPetImages(
        _ updated: PetImageSet,
        encodedImages: [ObjectIdentifier: Data] = [:],
        resetActivity: Bool = false,
        cleanup: @Sendable (
            PetImageStorage,
            [String: [String]],
            [String: [String]]
        ) async -> Void = { storage, old, new in
            await Task.detached { storage.removeObsoleteFiles(from: old, keeping: new) }.value
        }
    ) async throws {
        guard let directory = petImagesDirectoryURL else { throw CocoaError(.fileNoSuchFile) }
        let storage = PetImageStorage(directory: directory)
        let previous = petImages
        let oldFiles = storedImageFiles
        let staged = try await Task.detached(priority: .userInitiated) {
            let files = try storage.stage(updated, replacing: previous, files: oldFiles, encodedImages: encodedImages)
            let thumbnails = autoreleasepool { PetSpriteSheetImporter.thumbnails(for: updated) }
            return (files, thumbnails)
        }.value
        let newFiles = staged.0
        guard !isShuttingDown else {
            await Task.detached { storage.removeObsoleteFiles(from: newFiles, keeping: oldFiles) }.value
            throw CancellationError()
        }
        settings.petImageFiles = newFiles
        storedImageFiles = newFiles
        importedImages = updated
        imageThumbnails = staged.1
        imageSetDidChange(resetActivity: resetActivity)
        await cleanup(storage, oldFiles, newFiles)
    }

    func addImages(_ urls: [URL], to category: PetImageCategory) {
        Task { [weak self] in
            guard let self else { return }
            _ = await queueImageUpdate { await self.addImagesInOrder(urls, to: category) }
        }
    }

    private func addImagesInOrder(_ urls: [URL], to category: PetImageCategory) async -> Bool {
        guard !imageLoadFailed else {
            await showImageSaveError(PetImageStorageError.memoryBudgetExceeded)
            return false
        }
        var addedCount = 0
        var skippedCount = 0
        for url in urls {
            let optimized = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    PetSpriteSheetImporter.readPNG(from: url).flatMap(PetSpriteSheetImporter.optimizedImage)
                }
            }.value
            guard !isShuttingDown else { return false }
            guard let optimized else {
                skippedCount += 1
                continue
            }
            var updated = petImages
            updated[category].append(optimized.image)
            do {
                let encoded = [ObjectIdentifier(optimized.image): optimized.pngData]
                try await persistPetImages(updated, encodedImages: encoded)
                addedCount += 1
            } catch {
                await showImageSaveError(error)
                return false
            }
        }
        guard addedCount > 0 else {
            await showAlert(.imagesErrorTitle, .imagesErrorMessage)
            return false
        }
        if skippedCount > 0 {
            await showAlert(.imagesSkippedTitle, .imagesSkippedMessage)
        }
        return true
    }

    @discardableResult
    func removeImage(at index: Int, from category: PetImageCategory) -> Task<Void, Never>? {
        guard petImages[category].indices.contains(index) else { return nil }
        let target = petImages[category][index]
        return Task { [weak self] in
            guard let self else { return }
            _ = await queueImageUpdate {
                var updated = self.petImages
                guard !self.imageLoadFailed, updated[category].count > 1,
                      let currentIndex = updated[category].firstIndex(where: { $0 === target }) else { return false }
                updated[category].remove(at: currentIndex)
                return await self.saveImageEdit(updated)
            }
        }
    }

    func moveImage(from source: Int, to destination: Int, in category: PetImageCategory) {
        let images = petImages[category]
        guard source != destination,
              images.indices.contains(source), images.indices.contains(destination) else { return }
        let target = images[source]
        let anchor = images[destination]
        Task { [weak self] in
            guard let self else { return }
            _ = await queueImageUpdate {
                let current = self.petImages[category]
                guard !self.imageLoadFailed,
                      let sourceIndex = current.firstIndex(where: { $0 === target }),
                      let destinationIndex = current.firstIndex(where: { $0 === anchor }),
                      let reordered = moving(current, from: sourceIndex, to: destinationIndex) else { return false }
                var updated = self.petImages
                updated[category] = reordered
                return await self.saveImageEdit(updated)
            }
        }
    }

    private func saveImageEdit(_ updated: PetImageSet) async -> Bool {
        do {
            try await persistPetImages(updated)
            return true
        } catch {
            await showImageSaveError(error)
            return false
        }
    }
}
