import Foundation
import Testing
import WaddlyCore

private func spriteTestDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WaddlySpriteFrameTests-\(UUID().uuidString)", isDirectory: true)
}

private func removeSpriteTestDirectory(_ directory: URL) {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    do {
        try FileManager.default.removeItem(at: directory)
    } catch {
        Issue.record("Could not remove the temporary directory: \(error)")
    }
}

private func spriteFrameName() -> String {
    "\(UUID().uuidString).png"
}

@MainActor private func spriteStore(directory: URL) -> PetImageStore {
    let mirror = StoreLegacyMirror()
    return PetImageStore(
        directory: directory,
        legacyFiles: { mirror.files },
        writeLegacyFiles: { mirror.files = $0 },
        imagesDidChange: { _ in }
    )
}

private enum SpritePersistenceTestError: Error {
    case invalidSheet
}

private func spriteSheetCandidate() throws -> PetSheetCandidate {
    let data = try #require(spriteTestSheetData())
    guard case let .success(candidate) = PetSpriteSheetImporter.inspect(data) else {
        throw SpritePersistenceTestError.invalidSheet
    }
    return candidate
}

private func spriteSidecarExists(_ name: String, in directory: URL) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
}

// MARK: - Storage sidecars

@Test func storageWritesAndReadsTheSheetSidecars() throws {
    let directory = spriteTestDirectory()
    defer { removeSpriteTestDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    let sheetPNGData = try #require(spriteTestSheetData())
    var editing = spriteTestSheetEditing()
    editing.setAdjustment(
        FrameAdjustment(crop: SquareCrop(x: 22, y: 4, size: 14), offsetX: 2, offsetY: -1),
        for: .typing3
    )
    let manifest = ["idle": [spriteFrameName(), spriteFrameName()], "typing": [spriteFrameName()]]

    try storage.writeFrameEditingSource(
        PetImageEditingSource(editing: editing, sheetPNGData: sheetPNGData),
        manifest: manifest
    )

    #expect(spriteSidecarExists("source-sheet.png", in: directory))
    #expect(spriteSidecarExists("frame-edits.json", in: directory))
    #expect(try Data(contentsOf: directory.appendingPathComponent("source-sheet.png")) == sheetPNGData)

    let restored = try #require(storage.readFrameEditingSource(manifest: manifest))
    #expect(restored.editing == editing.normalized)
    #expect(restored.sheetPNGData == sheetPNGData)

    let editsURL = directory.appendingPathComponent("frame-edits.json")
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: editsURL)) as? [String: Any]
    #expect(object?.keys.sorted() == ["editing", "frameFiles"])
    #expect(object?["frameFiles"] as? [String: [String]] == manifest)
}

@Test func storageIgnoresEditsWrittenForAnotherManifest() throws {
    let directory = spriteTestDirectory()
    defer { removeSpriteTestDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    let sheetPNGData = try #require(spriteTestSheetData())
    let manifest = ["idle": [spriteFrameName()]]
    try storage.writeFrameEditingSource(
        PetImageEditingSource(editing: spriteTestSheetEditing(), sheetPNGData: sheetPNGData),
        manifest: manifest
    )

    #expect(storage.readFrameEditingSource(manifest: manifest) != nil)
    var changed = manifest
    changed["enter"] = [spriteFrameName()]
    #expect(storage.readFrameEditingSource(manifest: changed) == nil)
    #expect(storage.readFrameEditingSource(manifest: [:]) == nil)
}

@Test func storageRejectsMissingOrCorruptSheetAndEdits() throws {
    let directory = spriteTestDirectory()
    defer { removeSpriteTestDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    let source = try PetImageEditingSource(
        editing: spriteTestSheetEditing(),
        sheetPNGData: #require(spriteTestSheetData())
    )
    let manifest = ["idle": [spriteFrameName()]]
    try storage.writeFrameEditingSource(source, manifest: manifest)

    try FileManager.default.removeItem(at: directory.appendingPathComponent("source-sheet.png"))
    #expect(storage.readFrameEditingSource(manifest: manifest) == nil)

    try storage.writeFrameEditingSource(source, manifest: manifest)
    try Data("not a PNG".utf8).write(to: directory.appendingPathComponent("source-sheet.png"))
    #expect(storage.readFrameEditingSource(manifest: manifest) == nil)

    try storage.writeFrameEditingSource(source, manifest: manifest)
    try Data("{ not json".utf8).write(to: directory.appendingPathComponent("frame-edits.json"))
    #expect(storage.readFrameEditingSource(manifest: manifest) == nil)
}

@Test func storageRemovesSidecarsWhenThereIsNoSheetSource() throws {
    let directory = spriteTestDirectory()
    defer { removeSpriteTestDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    let manifest = ["idle": [spriteFrameName()]]
    let source = try PetImageEditingSource(
        editing: spriteTestSheetEditing(),
        sheetPNGData: #require(spriteTestSheetData())
    )
    let individual = PetImageEditingSource(
        editing: SpriteFrameEditing.identity(
            mode: .individualFrames,
            sourceSides: Array(repeating: 12, count: 9),
            cellSize: 0
        ),
        sheetPNGData: nil
    )
    let sheetWithoutPNG = PetImageEditingSource(editing: spriteTestSheetEditing(), sheetPNGData: nil)

    try storage.writeFrameEditingSource(source, manifest: manifest)
    #expect(spriteSidecarExists("source-sheet.png", in: directory))
    #expect(storage.readFrameEditingSource(manifest: manifest) != nil)

    try storage.writeFrameEditingSource(individual, manifest: manifest)
    #expect(!spriteSidecarExists("source-sheet.png", in: directory))
    #expect(!spriteSidecarExists("frame-edits.json", in: directory))
    #expect(storage.readFrameEditingSource(manifest: manifest) == nil)

    try storage.writeFrameEditingSource(source, manifest: manifest)
    try storage.writeFrameEditingSource(sheetWithoutPNG, manifest: manifest)
    #expect(!spriteSidecarExists("source-sheet.png", in: directory))
    #expect(!spriteSidecarExists("frame-edits.json", in: directory))

    try storage.writeFrameEditingSource(source, manifest: manifest)
    try storage.writeFrameEditingSource(nil, manifest: manifest)
    #expect(!spriteSidecarExists("source-sheet.png", in: directory))
    #expect(!spriteSidecarExists("frame-edits.json", in: directory))
    #expect(storage.readFrameEditingSource(manifest: manifest) == nil)
}

@Test func reconciliationLeavesTheFixedSidecarsAlone() throws {
    let directory = spriteTestDirectory()
    defer { removeSpriteTestDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let storage = PetImageStorage(directory: directory)
    let kept = spriteFrameName()
    let orphan = spriteFrameName()
    try Data("frame".utf8).write(to: directory.appendingPathComponent(kept))
    try Data("orphan".utf8).write(to: directory.appendingPathComponent(orphan))
    try storage.commitManifest(["idle": [kept]])
    let manifest = try #require(try storage.readManifest())
    try storage.writeFrameEditingSource(
        PetImageEditingSource(
            editing: spriteTestSheetEditing(),
            sheetPNGData: #require(spriteTestSheetData())
        ),
        manifest: manifest
    )

    let removed = try storage.reconcileFiles()

    #expect(removed == [orphan])
    #expect(spriteSidecarExists("source-sheet.png", in: directory))
    #expect(spriteSidecarExists("frame-edits.json", in: directory))
    #expect(storage.readFrameEditingSource(manifest: manifest) != nil)
}

// MARK: - PetSheetCandidate

@Test func sheetCandidateCarriesTheSheetPNGAndIdentityEditing() throws {
    let data = try #require(spriteTestSheetData())
    guard case let .success(candidate) = PetSpriteSheetImporter.inspect(data) else {
        Issue.record("the synthetic sheet must inspect")
        return
    }
    #expect(candidate.cellSize == 20)
    #expect(candidate.sheetPNGData == data)
    #expect(candidate.editingSource.editing == spriteTestSheetEditing())
    #expect(candidate.editingSource.sheetPNGData == data)
    #expect(candidate.images.editingSource?.editing == candidate.editingSource.editing)
    let sharesBuffer = data.withUnsafeBytes { input in
        candidate.sheetPNGData.withUnsafeBytes { sheet in
            input.baseAddress == sheet.baseAddress
        }
    }
    #expect(sharesBuffer)
}

@Test func downsampledSheetReencodesTheWorkingPNG() throws {
    let side = PetSpriteSheetImporter.maximumImageDimension * 3 + 3
    let image = try #require(spriteTestImage(width: side, height: side) { _, _ in .clear })
    let data = try #require(spriteTestPNGData(for: image))
    #expect(data.count <= PetSpriteSheetImporter.maximumFileSize)
    guard case let .success(candidate) = PetSpriteSheetImporter.inspect(data) else {
        Issue.record("the oversized transparent sheet must inspect")
        return
    }
    #expect(candidate.cellSize == PetSpriteSheetImporter.maximumImageDimension)
    #expect(candidate.sheetPNGData != data)
    let decoded = try #require(PetFrameSourceDecoder.sheetImage(from: candidate.sheetPNGData))
    #expect(decoded.width == PetSpriteSheetImporter.maximumImageDimension * 3)
    #expect(decoded.height == PetSpriteSheetImporter.maximumImageDimension * 3)
    #expect(candidate.images.editingSource?.sheetPNGData == candidate.sheetPNGData)
}

// MARK: - Store persist / restore

@Suite(.serialized) @MainActor struct SpriteFrameStoreTests {
    @Test func persistWritesSidecarsAndRestoreReattachesThem() async throws {
        let directory = spriteTestDirectory()
        defer { removeSpriteTestDirectory(directory) }
        let candidate = try spriteSheetCandidate()
        let store = spriteStore(directory: directory)
        try await store.persist(candidate.images)

        #expect(spriteSidecarExists("source-sheet.png", in: directory))
        #expect(spriteSidecarExists("frame-edits.json", in: directory))
        #expect(store.images.editingSource?.editing == candidate.editingSource.editing)

        let restored = spriteStore(directory: directory)
        try await restored.restore()
        #expect(restored.hasCompleteImageSet)
        let editingSource = try #require(restored.images.editingSource)
        #expect(editingSource.editing == candidate.editingSource.editing)
        #expect(editingSource.sheetPNGData == candidate.sheetPNGData)
    }

    @Test func sidecarFailureDoesNotFailACommittedFrameSave() async throws {
        let directory = spriteTestDirectory()
        defer { removeSpriteTestDirectory(directory) }
        let candidate = try spriteSheetCandidate()
        let store = spriteStore(directory: directory)
        try await store.persist(candidate.images)

        let editsURL = directory.appendingPathComponent("frame-edits.json")
        try FileManager.default.removeItem(at: editsURL)
        try FileManager.default.createDirectory(at: editsURL, withIntermediateDirectories: false)
        var updated = store.images
        updated[.idle].reverse()

        try await store.persist(updated)

        #expect(store.images[.idle].count == 2)
        let storage = PetImageStorage(directory: directory)
        #expect(try storage.readManifest() != nil)
        #expect(spriteSidecarExists("source-sheet.png", in: directory))
    }

    @Test func persistRemovesSidecarsWhenEditingIsCleared() async throws {
        let directory = spriteTestDirectory()
        defer { removeSpriteTestDirectory(directory) }
        let candidate = try spriteSheetCandidate()
        let store = spriteStore(directory: directory)
        try await store.persist(candidate.images)
        #expect(spriteSidecarExists("frame-edits.json", in: directory))

        var stripped = store.images
        stripped.editingSource = nil
        try await store.persist(stripped)

        #expect(!spriteSidecarExists("source-sheet.png", in: directory))
        #expect(!spriteSidecarExists("frame-edits.json", in: directory))
        let restored = spriteStore(directory: directory)
        try await restored.restore()
        #expect(restored.hasCompleteImageSet)
        #expect(restored.images.editingSource == nil)
    }

    @Test func legacyFrameSaveRestoresWithoutAnEditingSource() async throws {
        let directory = spriteTestDirectory()
        defer { removeSpriteTestDirectory(directory) }
        let store = spriteStore(directory: directory)
        var legacy = try storeExampleImages()
        legacy.editingSource = nil
        try await store.persist(legacy)

        #expect(!spriteSidecarExists("source-sheet.png", in: directory))
        #expect(!spriteSidecarExists("frame-edits.json", in: directory))
        #expect(store.images.editingSource == nil)

        let restored = spriteStore(directory: directory)
        try await restored.restore()
        #expect(restored.hasCompleteImageSet)
        #expect(restored.images.editingSource == nil)
    }
}
