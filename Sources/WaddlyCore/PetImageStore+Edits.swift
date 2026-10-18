import AppKit

/// Edit adapters for `PetImageStore`: decode work, the confirmation wait, and the identity-based
/// remove/reorder transactions. Each public entry point runs inside the store's queue, so the whole
/// operation — including a suspended confirmation — is serialized with every other edit.
public extension PetImageStore {
    /// Decode and append `urls` one at a time, committing each addition before moving on.
    func addImages(_ urls: [URL], to category: PetImageCategory) async -> PetImageAddOutcome {
        await perform { await self.addImagesInOrder(urls, to: category) } ?? .aborted
    }

    /// Decode a sheet and commit it after `confirm` accepts the preview.
    func importPetImage(
        from url: URL,
        confirm: @escaping @MainActor (NSImage, Int) async -> Bool
    ) async -> PetImageImportOutcome {
        await perform { await self.importPetImageInOrder(from: url, confirm: confirm) } ?? .aborted
    }

    /// Commit a frame set the user already reviewed.
    func confirmPetImage(
        _ images: PetImageSet,
        accepting: @escaping @MainActor () -> Bool = { true }
    ) async -> PetImageConfirmOutcome {
        await perform { await self.confirmPetImageInOrder(images, accepting: accepting) } ?? .aborted
    }

    /// Remove the frame at `index`, resolving it by identity inside the queue so a stale index from a
    /// suspended confirmation cannot remove the wrong frame. Returns `nil` when the index is out of
    /// range; the task reports a save failure through `onSaveError`.
    @discardableResult
    func removeImage(
        at index: Int,
        from category: PetImageCategory,
        onSaveError: (@MainActor (Error) async -> Void)? = nil
    ) -> Task<Void, Never>? {
        guard images[category].indices.contains(index) else { return nil }
        let target = images[category][index]
        return Task { [weak self] in
            guard let self else { return }
            _ = await queue {
                var updated = self.images
                guard !self.loadFailed, updated[category].count > 1,
                      let currentIndex = updated[category].firstIndex(where: { $0 === target }) else { return false }
                updated[category].remove(at: currentIndex)
                return await self.save(updated, onSaveError: onSaveError)
            }
        }
    }

    /// Move a frame, resolving source and destination by identity inside the queue so a reorder
    /// queued behind a suspended edit still lands against the frame the user grabbed.
    @discardableResult
    func moveImage(
        from source: Int,
        to destination: Int,
        in category: PetImageCategory,
        onSaveError: (@MainActor (Error) async -> Void)? = nil
    ) -> Task<Void, Never>? {
        let current = images[category]
        guard source != destination,
              current.indices.contains(source), current.indices.contains(destination) else { return nil }
        let target = current[source]
        let anchor = current[destination]
        return Task { [weak self] in
            guard let self else { return }
            _ = await queue {
                let categoryImages = self.images[category]
                guard !self.loadFailed,
                      let sourceIndex = categoryImages.firstIndex(where: { $0 === target }),
                      let destinationIndex = categoryImages.firstIndex(where: { $0 === anchor }),
                      let reordered = Self.moving(categoryImages, from: sourceIndex, to: destinationIndex)
                else { return false }
                var updated = self.images
                updated[category] = reordered
                return await self.save(updated, onSaveError: onSaveError)
            }
        }
    }

    private func addImagesInOrder(_ urls: [URL], to category: PetImageCategory) async -> PetImageAddOutcome {
        guard !loadFailed else { return .blocked }
        var addedCount = 0
        var skippedCount = 0
        for url in urls {
            let optimized = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    PetSpriteSheetImporter.readPNG(from: url).flatMap(PetSpriteSheetImporter.optimizedImage)
                }
            }.value
            guard !isShuttingDown else { return .aborted }
            guard let optimized else {
                skippedCount += 1
                continue
            }
            var updated = images
            updated[category].append(optimized.image)
            do {
                try await persist(updated, encodedImages: [ObjectIdentifier(optimized.image): optimized.pngData])
                addedCount += 1
            } catch {
                return .failed(error)
            }
        }
        guard addedCount > 0 else { return .skippedAll }
        return .added(skipped: skippedCount)
    }

    private func importPetImageInOrder(
        from url: URL,
        confirm: @escaping @MainActor (NSImage, Int) async -> Bool
    ) async -> PetImageImportOutcome {
        let prepared = await Task.detached(priority: .userInitiated) {
            autoreleasepool { () -> (PetImageSet, NSImage)? in
                guard let data = PetSpriteSheetImporter.readPNG(from: url),
                      let images = PetSpriteSheetImporter.frames(from: data),
                      let preview = PetSpriteSheetImporter.preview(from: data) else { return nil }
                return (images, preview)
            }
        }.value
        guard !isShuttingDown else { return .aborted }
        guard let (newImages, preview) = prepared else { return .invalid }
        guard await confirm(preview, Int(newImages[.idle][0].size.width)) else { return .cancelled }
        do {
            try await persist(newImages, resetActivity: true)
        } catch {
            return .failed(error)
        }
        clearLoadFailure()
        return .imported
    }

    private func confirmPetImageInOrder(
        _ images: PetImageSet,
        accepting: @escaping @MainActor () -> Bool
    ) async -> PetImageConfirmOutcome {
        guard accepting() else { return .aborted }
        do {
            try await persist(images, resetActivity: true)
        } catch {
            return .failed(error)
        }
        clearLoadFailure()
        return .confirmed
    }

    private func save(
        _ updated: PetImageSet,
        onSaveError: (@MainActor (Error) async -> Void)?
    ) async -> Bool {
        do {
            try await persist(updated)
            return true
        } catch {
            if let onSaveError {
                await onSaveError(error)
            }
            return false
        }
    }

    internal static func moving<Element>(_ elements: [Element], from source: Int, to destination: Int) -> [Element]? {
        guard elements.indices.contains(source), elements.indices.contains(destination) else { return nil }
        var result = elements
        let item = result.remove(at: source)
        result.insert(item, at: destination)
        return result
    }
}

/// What an incremental add did, so the app can choose which alert to show.
public enum PetImageAddOutcome: Sendable {
    /// The load-failure guard blocks edits until images are imported again.
    case blocked
    case failed(Error)
    /// `added` frames committed; `skipped` URLs could not be decoded.
    case added(skipped: Int)
    /// No URL could be decoded, so nothing changed.
    case skippedAll
    /// Shutdown rejected the edit or interrupted it between frames.
    case aborted
}

/// What a sheet import did, so the app can choose which alert to show.
public enum PetImageImportOutcome: Sendable {
    case imported
    /// The user declined the preview.
    case cancelled
    /// The file was not an acceptable transparent PNG sprite sheet.
    case invalid
    case failed(Error)
    case aborted
}

/// What a reviewed-set commit did, so the app can choose which alert to show.
public enum PetImageConfirmOutcome: Sendable {
    case confirmed
    case failed(Error)
    case aborted
}
