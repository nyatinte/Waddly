import AppKit
import WaddlyCore

extension AppDelegate {
    /// Serialize complete image transactions, including the manifest commit (run on a worker).
    ///
    /// This is the exclusive-access guarantee `PetImageStorage` requires across the
    /// stage → commit → reconcile transaction: operations queue behind one another and no extra lock
    /// is taken.
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

    /// Persist a frame set with the on-disk manifest as the source of truth.
    ///
    /// Order matters: stage the new files, commit the manifest atomically, publish the new set, then
    /// sweep unreferenced files. A failed commit removes only the files this call staged and keeps
    /// the previous manifest and images. Cleanup runs last and is non-fatal; leftovers are swept on
    /// the next launch. The legacy `UserDefaults` mirror is written only after a successful commit
    /// so a downgrade still finds the frames.
    func persistPetImages(
        _ updated: PetImageSet,
        encodedImages: [ObjectIdentifier: Data] = [:],
        resetActivity: Bool = false,
        cleanup: @Sendable (PetImageStorage) async -> Void = { storage in
            await Task.detached { _ = try? storage.reconcileFiles() }.value
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
            await discardStagedFiles(storage, staged: newFiles, committed: oldFiles)
            throw CancellationError()
        }
        do {
            try await Task.detached(priority: .userInitiated) {
                try storage.commitManifest(newFiles)
            }.value
        } catch {
            await discardStagedFiles(storage, staged: newFiles, committed: oldFiles)
            throw error
        }
        settings.petImageFiles = newFiles
        storedImageFiles = newFiles
        importedImages = updated
        imageThumbnails = staged.1
        imageSetDidChange(resetActivity: resetActivity)
        await cleanup(storage)
    }

    /// Remove only the files this save just created, leaving the committed set untouched.
    private func discardStagedFiles(
        _ storage: PetImageStorage,
        staged: [String: [String]],
        committed: [String: [String]]
    ) async {
        let created = Set(staged.values.flatMap(\.self)).subtracting(committed.values.flatMap(\.self))
        guard !created.isEmpty else { return }
        let directory = storage.directory
        await Task.detached(priority: .userInitiated) {
            for name in created {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }.value
    }

    func addImages(_ urls: [URL], to category: PetImageCategory) {
        Task { [weak self] in
            guard let self else { return }
            _ = await queueImageUpdate { await self.addImagesInOrder(urls, to: category) }
        }
    }

    private func addImagesInOrder(_ urls: [URL], to category: PetImageCategory) async -> Bool {
        guard !imageLoadFailed else {
            await showImageLoadError()
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

    @discardableResult
    func moveImage(from source: Int, to destination: Int, in category: PetImageCategory) -> Task<Void, Never>? {
        let images = petImages[category]
        guard source != destination,
              images.indices.contains(source), images.indices.contains(destination) else { return nil }
        let target = images[source]
        let anchor = images[destination]
        return Task { [weak self] in
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
