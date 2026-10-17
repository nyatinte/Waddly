import AppKit

/// The main-actor owner of the pet-image lifecycle: the loaded frames, the committed filenames, the
/// thumbnails, the load-failure guard, and the serialized edit queue.
///
/// The store is the single writer for image state. Every edit runs inside `queue`, so one
/// stage → commit → publish → clean-up transaction is never interleaved with another edit or with
/// the confirmation wait of an import. `persist` performs that transaction itself: it stages new
/// frame files on a worker, commits the manifest atomically, publishes the new state through
/// `imagesDidChange`, and only then sweeps unreferenced files. A failed commit removes only the
/// files this call staged and leaves the previous manifest and images untouched.
///
/// The store never reads app preferences, windows, or localized strings. The on-disk directory, the
/// legacy `UserDefaults` mirror, and the publish callback are injected, so alerts, confirmation
/// sheets, and panel/animation refresh stay in the app layer. The edit adapters live in
/// `PetImageStore+Edits.swift`.
@MainActor
public final class PetImageStore {
    public typealias ManifestFiles = [String: [String]]

    /// The on-disk directory, or `nil` when the app has no image location. Saves then throw
    /// `CocoaError(.fileNoSuchFile)` and restores are a no-op.
    public let directory: URL?
    /// The loaded frames, or `nil` until a non-empty manifest is restored.
    public var importedImages: PetImageSet?
    /// The filenames the committed manifest references, in category order.
    public private(set) var files: ManifestFiles = [:]
    /// At most 128 px thumbnails for the current frames, keyed by frame identity.
    public private(set) var thumbnails: [ObjectIdentifier: NSImage] = [:]
    /// Set when decoding could not materialize every frame the manifest references.
    public private(set) var loadFailed = false
    /// The error behind `loadFailed`, kept so an unreadable manifest is not reported as a
    /// memory-budget failure.
    public private(set) var loadError: Error?
    /// Set once the owner is terminating: queued edits are rejected and a stage in flight is rolled
    /// back instead of committed.
    public private(set) var isShuttingDown = false

    public var images: PetImageSet {
        importedImages ?? PetImageSet()
    }

    public var hasCompleteImageSet: Bool {
        images.isComplete
    }

    private let legacyFiles: () -> ManifestFiles
    private let writeLegacyFiles: (ManifestFiles) -> Void
    private let imagesDidChange: (Bool) -> Void
    private var pendingMutation: Task<Void, Never>?

    public init(
        directory: URL?,
        legacyFiles: @escaping () -> ManifestFiles,
        writeLegacyFiles: @escaping (ManifestFiles) -> Void,
        imagesDidChange: @escaping (Bool) -> Void
    ) {
        self.directory = directory
        self.legacyFiles = legacyFiles
        self.writeLegacyFiles = writeLegacyFiles
        self.imagesDidChange = imagesDidChange
    }

    public func beginShutdown() {
        isShuttingDown = true
    }

    /// Serializes `operation` behind the in-flight edit and rejects it after shutdown.
    ///
    /// This is the exclusive-access guarantee `PetImageStorage` requires across the
    /// stage → commit → reconcile transaction: operations queue behind one another and no extra lock
    /// is taken.
    @discardableResult
    public func queue(_ operation: @escaping @MainActor () async -> Bool) async -> Bool {
        await perform(operation) ?? false
    }

    /// Restores the last committed frame set, treating the on-disk manifest as authoritative.
    ///
    /// When the manifest is missing, the legacy mirror is committed to disk before the reconciling
    /// sweep so the frames it still names are protected. A manifest that cannot be read leaves the
    /// store with `loadFailed` set and throws, so the app can report it and keep edits blocked.
    /// Reconciliation runs only when the decoded set is complete and the mirror still agrees with the
    /// manifest; disagreement can mean another build wrote frames after this manifest, so those
    /// frames stay until a deliberate save.
    ///
    /// Callers that want the restore serialized with edits must run it inside `queue` themselves;
    /// nesting it would deadlock the queue.
    public func restore() async throws {
        guard let directory else { return }
        let storage = PetImageStorage(directory: directory)
        let legacy = legacyFiles()
        do {
            let restored = try await Task.detached(priority: .userInitiated) {
                try autoreleasepool { () -> RestoredPetImages in
                    let manifest = try committedOrMigratedManifest(storage, legacy: legacy)
                    let loaded = try storage.load(manifest)
                    return RestoredPetImages(
                        manifest: manifest,
                        images: loaded.0,
                        files: loaded.1,
                        thumbnails: PetSpriteSheetImporter.thumbnails(for: loaded.0)
                    )
                }
            }.value
            guard !isShuttingDown else { return }
            files = restored.manifest
            let referencedNames = Set(restored.manifest.values.flatMap(\.self))
            let decodedNames = Set(restored.files.values.flatMap(\.self))
            loadFailed = referencedNames != decodedNames
            loadError = nil
            if !restored.manifest.isEmpty {
                importedImages = restored.images
                thumbnails = restored.thumbnails
            }
            if !loadFailed, legacy == restored.manifest {
                await reconcile(storage)
            }
        } catch {
            loadFailed = true
            loadError = error
            files = legacy
            throw error
        }
    }

    /// Persists a frame set with the on-disk manifest as the source of truth.
    ///
    /// Order matters: stage the new files, commit the manifest atomically, publish the new set
    /// through `imagesDidChange`, then sweep unreferenced files. A failed commit removes only the
    /// files this call staged and keeps the previous manifest and images. Cleanup runs last and is
    /// non-fatal; leftovers are swept on the next launch. The legacy mirror is written only after a
    /// successful commit so a downgrade still finds the frames.
    ///
    /// This transaction primitive does not enqueue itself: production callers must already own
    /// `queue`. Edit adapters do so for their whole operation; enqueueing again would deadlock.
    public func persist(
        _ updated: PetImageSet,
        encodedImages: [ObjectIdentifier: Data] = [:],
        resetActivity: Bool = false,
        cleanup: @escaping @Sendable (PetImageStorage) async -> Void = { storage in
            await Task.detached { _ = try? storage.reconcileFiles() }.value
        }
    ) async throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        let storage = PetImageStorage(directory: directory)
        let previous = images
        let oldFiles = files
        let staged = try await Task.detached(priority: .userInitiated) {
            let files = try storage.stage(
                updated,
                replacing: previous,
                files: oldFiles,
                encodedImages: encodedImages
            )
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
        writeLegacyFiles(newFiles)
        files = newFiles
        importedImages = updated
        thumbnails = staged.1
        imagesDidChange(resetActivity)
        await cleanup(storage)
    }

    /// Clears the load-failure guard after an edit committed a known-good set.
    func clearLoadFailure() {
        loadFailed = false
        loadError = nil
    }

    /// Runs `operation` after the in-flight edit, returning `nil` when the store is shutting down.
    func perform<T: Sendable>(_ operation: @escaping @MainActor () async -> T) async -> T? {
        let previous = pendingMutation
        let task = Task { @MainActor () -> T? in
            await previous?.value
            guard !isShuttingDown else { return nil }
            return await operation()
        }
        pendingMutation = Task { _ = await task.value }
        return await task.value
    }

    /// Sweep files the committed manifest no longer references. Best effort: a failure retries on the
    /// next launch without blocking the images already displayed.
    private func reconcile(_ storage: PetImageStorage) async {
        await Task.detached(priority: .utility) {
            _ = try? storage.reconcileFiles()
        }.value
    }

    /// Remove only the files this save just created, leaving the committed set untouched.
    private func discardStagedFiles(
        _ storage: PetImageStorage,
        staged: ManifestFiles,
        committed: ManifestFiles
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
}

/// The manifest, decoded images, their frame names, and thumbnails restored from disk in one pass.
private struct RestoredPetImages {
    let manifest: [String: [String]]
    let images: PetImageSet
    let files: [String: [String]]
    let thumbnails: [ObjectIdentifier: NSImage]
}

/// Read the committed manifest, or migrate the legacy defaults to disk when it is missing.
///
/// Migration writes the mirror first so the reconciliation that follows can never delete a frame
/// the legacy state still referenced. With no manifest and no legacy mirror, nothing is committed:
/// the returned empty manifest only means "show nothing", while the reconciling sweep sees `nil`
/// and leaves the on-disk frames of uncertain provenance untouched. An explicitly committed empty
/// manifest is different and stays authoritative.
private func committedOrMigratedManifest(
    _ storage: PetImageStorage,
    legacy: [String: [String]]
) throws -> [String: [String]] {
    if let committed = try storage.readManifest() {
        return committed
    }
    guard !legacy.isEmpty else { return [:] }
    try storage.commitManifest(legacy)
    return legacy
}
