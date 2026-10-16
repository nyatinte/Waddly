import AppKit

/// File work runs on a worker task. Image values are treated as immutable snapshots.
///
/// The JSON manifest in `directory` is the source of truth for which frame files compose the set.
/// `readManifest()` returns `nil` until a manifest exists so callers can migrate legacy defaults by
/// committing one, and `reconcileFiles()` compares the manifest against directory metadata without
/// decoding images.
public struct PetImageStorage: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Location of the atomic JSON manifest inside `directory`.
    public var manifestURL: URL {
        directory.appendingPathComponent(Self.manifestFilename)
    }

    /// Returns the committed manifest, or `nil` when no manifest file exists yet.
    ///
    /// A manifest that exists but cannot be read or decoded as `[String: [String]]` throws
    /// `PetImageManifestError.unreadable`. Callers must treat that as authoritative and must not
    /// reconcile (delete) any files until a readable manifest is available.
    public func readManifest() throws -> [String: [String]]? {
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
                return nil
            }
            throw PetImageManifestError.unreadable
        }
        do {
            return try JSONDecoder().decode([String: [String]].self, from: data)
        } catch {
            throw PetImageManifestError.unreadable
        }
    }

    /// Atomically replaces the manifest with `manifest` encoded as JSON.
    ///
    /// The new bytes are written to a sibling temporary file and renamed over the manifest, so a
    /// process terminated mid-commit leaves either the previous manifest or the new one, never a
    /// partial file. The rename is not fsynced: power loss can still lose the most recent commit or
    /// leave the previous manifest. On failure the previously committed manifest is unchanged.
    public func commitManifest(_ manifest: [String: [String]]) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        } catch {
            throw PetImageManifestError.commitFailed
        }
    }

    /// Removes only unreferenced frame files, using filesystem metadata and never decoding images.
    ///
    /// The committed manifest is the sole authority. A missing manifest is a no-op; an unreadable
    /// manifest throws `PetImageManifestError.unreadable` before anything is deleted. Every name the
    /// manifest references is protected even when its file is missing or undecodable. Only entries
    /// named `<uuid>.png` that are regular files directly inside `directory` are collected;
    /// symlinks, directories, and unrelated names are preserved.
    ///
    /// Returns the removed names. Repeated calls are idempotent. A removal failure throws
    /// `PetImageCleanupError.failed` after the manifest commit is already durable, so cleanup can be
    /// retried without saving again.
    @discardableResult
    public func reconcileFiles() throws -> [String] {
        guard let manifest = try readManifest() else { return [] }
        let referenced = Set(manifest.values.flatMap(\.self))
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            throw PetImageCleanupError.failed
        }
        var removed: [String] = []
        for entry in entries {
            let name = entry.lastPathComponent
            guard Self.isFrameFilename(name), !referenced.contains(name) else { continue }
            let values: URLResourceValues
            do {
                values = try entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            } catch {
                throw PetImageCleanupError.failed
            }
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            do {
                try FileManager.default.removeItem(at: entry)
                removed.append(name)
            } catch {
                throw PetImageCleanupError.failed
            }
        }
        return removed
    }

    public func load(_ manifest: [String: [String]]) throws -> (PetImageSet, [String: [String]]) {
        var images = PetImageSet()
        var files: [String: [String]] = [:]
        for category in PetImageCategory.allCases {
            for name in manifest[category.rawValue] ?? [] {
                guard Self.isFrameFilename(name) else { continue }
                let url = directory.appendingPathComponent(name)
                guard let image = PetSpriteSheetImporter.load(from: url) else { continue }
                images[category].append(image)
                files[category.rawValue, default: []].append(name)
                guard images.isWithinMemoryBudget else { throw PetImageStorageError.memoryBudgetExceeded }
            }
        }
        return (images, files)
    }

    /// Stage only new frames. Existing filenames survive reorders and removals.
    /// The caller commits the returned manifest before removing obsolete files.
    public func stage(
        _ images: PetImageSet,
        replacing previous: PetImageSet,
        files: [String: [String]],
        encodedImages: [ObjectIdentifier: Data] = [:]
    ) throws -> [String: [String]] {
        guard images.isWithinMemoryBudget else { throw PetImageStorageError.memoryBudgetExceeded }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var reusable: [ObjectIdentifier: String] = [:]
        for category in PetImageCategory.allCases {
            let names = files[category.rawValue] ?? []
            guard names.count == previous[category].count else { continue }
            for (image, name) in zip(previous[category], names) where Self.isFrameFilename(name) {
                reusable[ObjectIdentifier(image)] = name
            }
        }
        var created: [URL] = []
        var result: [String: [String]] = [:]
        do {
            for category in PetImageCategory.allCases {
                for image in images[category] {
                    if let name = reusable[ObjectIdentifier(image)] {
                        result[category.rawValue, default: []].append(name)
                        continue
                    }
                    let name = "\(UUID().uuidString).png"
                    let url = directory.appendingPathComponent(name)
                    try autoreleasepool {
                        let existingData = encodedImages[ObjectIdentifier(image)]
                        let encoded = existingData ?? PetSpriteSheetImporter.pngData(for: image)
                        guard let data = encoded,
                              data.count <= PetSpriteSheetImporter.maximumFileSize
                        else {
                            throw CocoaError(.fileWriteOutOfSpace)
                        }
                        try data.write(to: url, options: .atomic)
                    }
                    created.append(url)
                    result[category.rawValue, default: []].append(name)
                }
            }
        } catch {
            created.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
        return result
    }

    public func removeObsoleteFiles(from old: [String: [String]], keeping current: [String: [String]]) {
        let retained = Set(current.values.flatMap(\.self))
        for name in old.values.flatMap(\.self) where Self.isFrameFilename(name) && !retained.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static func isFrameFilename(_ name: String) -> Bool {
        name.hasSuffix(".png") && UUID(uuidString: String(name.dropLast(4))) != nil
    }

    private static let manifestFilename = "manifest.json"
}

public enum PetImageStorageError: Error {
    case memoryBudgetExceeded
}

/// Manifest read and commit failures. Kept separate from `PetImageStorageError` so a corrupt or
/// unwritable manifest is never reported as a memory-budget failure.
public enum PetImageManifestError: Error, Equatable {
    /// The manifest exists but could not be read or decoded.
    case unreadable
    /// The new manifest could not be written; the previous committed manifest is unchanged.
    case commitFailed
}

/// Reconciliation failure while deleting an unreferenced file. The manifest commit is already
/// durable, so this is retryable independently of the save that produced it.
public enum PetImageCleanupError: Error, Equatable {
    case failed
}
