import AppKit
import Testing
import WaddlyCore

/// In-memory stand-in for the legacy `UserDefaults` mirror the store injects.
@MainActor final class StoreLegacyMirror {
    var files: [String: [String]] = [:]
}

/// Records save failures reported by the store's edit adapters.
@MainActor final class StoreFailureRecorder {
    var errors: [Error] = []
}

@MainActor func makeImageStore(mirror: StoreLegacyMirror = StoreLegacyMirror()) -> PetImageStore {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WaddlyStoreTests-\(UUID().uuidString)", isDirectory: true)
    return PetImageStore(
        directory: directory,
        legacyFiles: { mirror.files },
        writeLegacyFiles: { mirror.files = $0 },
        imagesDidChange: { _ in }
    )
}

func storeExampleImages() throws -> PetImageSet {
    let url = try #require(
        Bundle.module.url(forResource: "nyatinte-bot-3x3", withExtension: "png", subdirectory: "Fixtures")
    )
    return try #require(PetSpriteSheetImporter.frames(from: Data(contentsOf: url)))
}

func storeFrameData(in directory: URL) throws -> [String: Data] {
    let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let frames = urls.filter { $0.pathExtension == "png" }
    return try Dictionary(uniqueKeysWithValues: frames.map { try ($0.lastPathComponent, Data(contentsOf: $0)) })
}

func storeCommittedManifest(in storage: PetImageStorage) throws -> [String: [String]] {
    let manifest = try storage.readManifest()
    return try #require(manifest)
}
