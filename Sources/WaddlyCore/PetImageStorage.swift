import AppKit
import ImageIO

/// File work runs on a worker task. Image values are treated as immutable snapshots.
///
/// The JSON manifest in `directory` is the source of truth for which frame files compose the set.
/// `readManifest()` returns `nil` until a manifest exists so callers can migrate legacy defaults by
/// committing one, and `reconcileFiles()` compares the manifest against directory metadata without
/// decoding images. A missing manifest is `nil`; an explicitly committed empty manifest is `[:]`,
/// and the two are not interchangeable because `[:]` authorizes removing every frame.
///
/// Callers must hold exclusive access to `directory` across the stage → commit → reconcile
/// transaction; this type takes no lock. `reconcileFiles()` deletes anything the manifest read at
/// call time does not reference, so a concurrent `stage` could otherwise be collected before its
/// commit.
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
    /// Fixed sidecar names, deliberately not `<uuid>.png`, so `reconcileFiles()` never collects them.
    private static let sourceSheetFilename = "source-sheet.png"
    private static let frameEditsFilename = "frame-edits.json"
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

/// Persistence for the frame editor's source sheet and per-slot edits.
///
/// Both files live in the image directory under fixed names (`source-sheet.png` and
/// `frame-edits.json`), which `reconcileFiles()` leaves alone. The JSON records the manifest it was
/// written against, so a pair left over from an earlier frame set is ignored rather than applied to
/// frames it does not describe. Only sheet mode is persisted: individual-frame editing is derived
/// from the frames themselves at restore time.
public extension PetImageStorage {
    /// Reads the persisted sheet and edits, or `nil` when they do not describe `manifest`.
    ///
    /// The sheet's pixel dimensions are read from the PNG header and must match the stored cell size;
    /// a sheet that does not describe those edits is ignored rather than applied.
    func readFrameEditingSource(manifest: [String: [String]]) -> PetImageEditingSource? {
        guard let data = sidecarData(Self.frameEditsFilename),
              let stored = decodeFrameEdits(data),
              stored.frameFiles == manifest,
              stored.editing.mode == .sheet,
              stored.editing.cellSize > 0,
              let sheetPNGData = sidecarData(Self.sourceSheetFilename),
              Self.hasPNGSignature(sheetPNGData),
              Self.sheetPixelSide(sheetPNGData) == stored.editing.cellSize * 3
        else { return nil }
        return PetImageEditingSource(
            editing: stored.editing.normalized,
            sheetPNGData: sheetPNGData
        )
    }

    /// Writes the sheet and edits, or removes both sidecars when there is nothing sheet-based to keep.
    ///
    /// The PNG is written before the JSON so the JSON always describes a sheet that exists. Callers
    /// treat failures as best effort: a sidecar problem must never fail an already-committed save.
    func writeFrameEditingSource(
        _ source: PetImageEditingSource?,
        manifest: [String: [String]]
    ) throws {
        guard let source, source.editing.mode == .sheet,
              let sheetPNGData = source.sheetPNGData, !sheetPNGData.isEmpty
        else {
            try removeFrameEditingSidecars()
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try sheetPNGData.write(to: sourceSheetURL, options: .atomic)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = StoredFrameEdits(frameFiles: manifest, editing: source.editing.normalized)
        try encoder.encode(payload).write(to: frameEditsURL, options: .atomic)
    }

    private var sourceSheetURL: URL {
        directory.appendingPathComponent(Self.sourceSheetFilename)
    }

    private var frameEditsURL: URL {
        directory.appendingPathComponent(Self.frameEditsFilename)
    }

    private func sidecarData(_ filename: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(filename))
    }

    private func decodeFrameEdits(_ data: Data) -> StoredFrameEdits? {
        try? JSONDecoder().decode(StoredFrameEdits.self, from: data)
    }

    private func removeFrameEditingSidecars() throws {
        for url in [sourceSheetURL, frameEditsURL] {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                guard Self.isMissingFileError(error) else { throw error }
            }
        }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError
    }

    private static func hasPNGSignature(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    /// The side of a square PNG read from its header, or `nil` when it is not a readable square.
    ///
    /// Only metadata is read (`kCGImageSourceShouldCache: false`); the sheet pixels are never decoded
    /// here, so restoring a large sheet stays cheap.
    private static func sheetPixelSide(_ data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, width == height
        else { return nil }
        return width
    }
}

/// The on-disk `frame-edits.json` shape: the frame manifest the edits belong to plus the editing.
private struct StoredFrameEdits: Codable {
    let frameFiles: [String: [String]]
    let editing: SpriteFrameEditing
}
