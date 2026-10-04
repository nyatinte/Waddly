import AppKit

/// File work runs on a worker task. Image values are treated as immutable snapshots.
public struct PetImageStorage: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
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
}

public enum PetImageStorageError: Error {
    case memoryBudgetExceeded
}
