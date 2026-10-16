import Foundation
import Testing
import WaddlyCore

private func makeStorageDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WaddlyManifestTests-\(UUID().uuidString)", isDirectory: true)
}

private func removeStorageDirectory(_ directory: URL) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    try? FileManager.default.removeItem(at: directory)
}

private func fixtureImages() throws -> PetImageSet {
    let url = try #require(
        Bundle.module.url(forResource: "nyatinte-bot-3x3", withExtension: "png", subdirectory: "Fixtures")
    )
    let data = try Data(contentsOf: url)
    return try #require(PetSpriteSheetImporter.frames(from: data))
}

private func writeFrame(_ name: String, in directory: URL, contents: String = "frame") throws {
    try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
}

private func frameName() -> String {
    "\(UUID().uuidString).png"
}

private func directoryEntries(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

@Test func missingManifestIsNilAndReconciliationRemovesNothing() throws {
    let directory = makeStorageDirectory()
    defer { removeStorageDirectory(directory) }
    let storage = PetImageStorage(directory: directory)

    #expect(try storage.readManifest() == nil)
    #expect(try storage.reconcileFiles().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: storage.manifestURL.path))
}

@Test func manifestRoundTripsThroughAtomicJSON() throws {
    let directory = makeStorageDirectory()
    defer { removeStorageDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    let manifest = ["idle": [frameName()], "typing": [frameName(), frameName()]]

    try storage.commitManifest(manifest)

    #expect(try storage.readManifest() == manifest)
    let persisted = try Data(contentsOf: storage.manifestURL)
    let object = try JSONSerialization.jsonObject(with: persisted) as? [String: [String]]
    #expect(object == manifest)
}

@Test func malformedManifestThrowsAndPreservesEveryFile() throws {
    let directory = makeStorageDirectory()
    defer { removeStorageDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let referenced = frameName()
    let orphan = frameName()
    try writeFrame(referenced, in: directory)
    try writeFrame(orphan, in: directory)
    try Data("{ this is not json".utf8).write(to: storage.manifestURL)

    #expect(throws: PetImageManifestError.unreadable) { try storage.readManifest() }
    #expect(throws: PetImageManifestError.unreadable) { try storage.reconcileFiles() }

    let expected = Set([referenced, orphan, storage.manifestURL.lastPathComponent])
    let entries = try directoryEntries(in: directory)
    #expect(Set(entries) == expected)
}

@Test func wrongShapeManifestThrows() throws {
    let directory = makeStorageDirectory()
    defer { removeStorageDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(#"{"idle": 7}"#.utf8).write(to: storage.manifestURL)

    #expect(throws: PetImageManifestError.unreadable) { try storage.readManifest() }
}

@Test func interruptionBeforeCommitRestoresTheCommittedSet() throws {
    let directory = makeStorageDirectory()
    defer { removeStorageDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    let first = try fixtureImages()
    let committed = try storage.stage(first, replacing: PetImageSet(), files: [:])
    try storage.commitManifest(committed)

    // A second save stages new files but is interrupted before the manifest is committed.
    let second = try fixtureImages()
    let staged = try storage.stage(second, replacing: first, files: committed)
    let committedNames = Set(committed.values.flatMap(\.self))
    let stagedNames = Set(staged.values.flatMap(\.self))
    #expect(committedNames.isDisjoint(with: stagedNames))

    let restarted = PetImageStorage(directory: directory)
    #expect(try restarted.readManifest() == committed)
    let removed = try restarted.reconcileFiles()
    #expect(Set(removed) == stagedNames)
    let entries = try directoryEntries(in: directory)
    let remaining = Set(entries)
    #expect(remaining == committedNames.union([restarted.manifestURL.lastPathComponent]))
    #expect(try restarted.load(committed).0.isComplete)
}

@Test func interruptionAfterCommitKeepsTheNewSet() throws {
    let directory = makeStorageDirectory()
    defer { removeStorageDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    let first = try fixtureImages()
    let committed = try storage.stage(first, replacing: PetImageSet(), files: [:])
    try storage.commitManifest(committed)

    let second = try fixtureImages()
    let staged = try storage.stage(second, replacing: first, files: committed)
    try storage.commitManifest(staged)
    let committedNames = Set(committed.values.flatMap(\.self))
    let stagedNames = Set(staged.values.flatMap(\.self))
    #expect(committedNames.isDisjoint(with: stagedNames))

    let restarted = PetImageStorage(directory: directory)
    #expect(try restarted.readManifest() == staged)
    let removed = try restarted.reconcileFiles()
    #expect(Set(removed) == committedNames)
    let entries = try directoryEntries(in: directory)
    let remaining = Set(entries)
    #expect(remaining == stagedNames.union([restarted.manifestURL.lastPathComponent]))
    #expect(try restarted.load(staged).0.isComplete)
}

@Test func reconciliationIsIdempotent() throws {
    let directory = makeStorageDirectory()
    defer { removeStorageDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    let first = try fixtureImages()
    let committed = try storage.stage(first, replacing: PetImageSet(), files: [:])
    try storage.commitManifest(committed)
    let second = try fixtureImages()
    _ = try storage.stage(second, replacing: first, files: committed)

    let firstPass = try storage.reconcileFiles()
    #expect(!firstPass.isEmpty)
    let afterFirstPass = try directoryEntries(in: directory)
    #expect(try storage.reconcileFiles().isEmpty)
    #expect(try storage.reconcileFiles().isEmpty)
    #expect(try directoryEntries(in: directory) == afterFirstPass)
}

@Test func reconciliationPreservesReferencedUndecodableAndUnrelatedEntries() throws {
    let directory = makeStorageDirectory()
    defer { removeStorageDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let referencedUndecodable = frameName()
    let orphan = frameName()
    let unrelatedText = "notes.txt"
    let unrelatedPng = "not-a-uuid.png"
    let symlink = frameName()
    let directoryEntry = frameName()
    let symlinkTarget = "shared.bin"

    try writeFrame(referencedUndecodable, in: directory, contents: "not a png")
    try writeFrame(orphan, in: directory)
    try writeFrame(unrelatedText, in: directory)
    try writeFrame(unrelatedPng, in: directory)
    try writeFrame(symlinkTarget, in: directory)
    try FileManager.default.createSymbolicLink(
        at: directory.appendingPathComponent(symlink),
        withDestinationURL: directory.appendingPathComponent(symlinkTarget)
    )
    try FileManager.default.createDirectory(
        at: directory.appendingPathComponent(directoryEntry),
        withIntermediateDirectories: false
    )
    try storage.commitManifest(["idle": [referencedUndecodable]])

    #expect(try storage.load(["idle": [referencedUndecodable]]).0[.idle].isEmpty)

    let removed = try storage.reconcileFiles()
    #expect(removed == [orphan])
    for name in [referencedUndecodable, unrelatedText, unrelatedPng, symlink, directoryEntry, symlinkTarget] {
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
    }
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(orphan).path))
}

@Test func cleanupFailureIsDistinctAndRetryable() throws {
    let directory = makeStorageDirectory()
    defer { removeStorageDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let referenced = frameName()
    let orphan = frameName()
    try writeFrame(referenced, in: directory)
    try writeFrame(orphan, in: directory)
    try storage.commitManifest(["idle": [referenced]])

    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
    #expect(throws: PetImageCleanupError.failed) { try storage.reconcileFiles() }
    #expect(try storage.readManifest() == ["idle": [referenced]])
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(orphan).path))

    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    #expect(try storage.reconcileFiles() == [orphan])
}

@Test func commitFailurePreservesTheCommittedManifest() throws {
    let directory = makeStorageDirectory()
    defer { removeStorageDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    let committed = ["idle": [frameName()]]
    try storage.commitManifest(committed)

    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
    let replacement = ["idle": [frameName(), frameName()]]
    #expect(throws: PetImageManifestError.commitFailed) { try storage.commitManifest(replacement) }
    #expect(try storage.readManifest() == committed)

    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    #expect(try storage.readManifest() == committed)
}

@Test func stageFailurePreservesTheCommittedSet() throws {
    let directory = makeStorageDirectory()
    defer { removeStorageDirectory(directory) }
    let storage = PetImageStorage(directory: directory)
    let previous = try fixtureImages()
    let committed = try storage.stage(previous, replacing: PetImageSet(), files: [:])
    try storage.commitManifest(committed)

    let replacement = try fixtureImages()
    let oversized = Data(count: PetSpriteSheetImporter.maximumFileSize + 1)
    #expect(throws: CocoaError.self) {
        try storage.stage(
            replacement,
            replacing: previous,
            files: committed,
            encodedImages: [ObjectIdentifier(replacement[.typing][0]): oversized]
        )
    }
    #expect(try storage.readManifest() == committed)
    let expected = Set(committed.values.flatMap(\.self)).union([storage.manifestURL.lastPathComponent])
    let entries = try directoryEntries(in: directory)
    #expect(Set(entries) == expected)
    #expect(try storage.load(committed).0.isComplete)
}
