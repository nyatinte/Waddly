import AppKit
import Testing
import UniformTypeIdentifiers
@testable import WaddlyApp

@Test func copyingShareAssetsWritesTheirNativePasteboardTypes() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("WaddlyTests.share.\(UUID().uuidString)"))
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    let movie = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])

    #expect(PetShareClipboard.copyPNG(png, to: pasteboard))
    #expect(pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.png.identifier)) == png)
}

@Test func copyingTheMovieNamesAFileSoUploadTargetsCanAttachIt() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("WaddlyTests.share.\(UUID().uuidString)"))
    let movie = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])
    let published = URL(fileURLWithPath: "/tmp/WaddlyTests/pet-animation.mp4")

    #expect(PetShareClipboard.copyMovie(movie, fileURL: published, to: pasteboard))
    #expect(pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier)) == movie)
    #expect(pasteboard.string(forType: .fileURL) == published.absoluteString)
    #expect((pasteboard.pasteboardItems ?? []).count == 1)
}

@Test func publishingForThePasteboardOutlivesTheExportItCameFrom() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WaddlyTests.publish.\(UUID().uuidString)", isDirectory: true)
    let movie = Data([0x01, 0x02])

    let published = try #require(PetShareClipboard.publishForPasteboard(movie, named: "pet-animation.mp4", in: root))
    #expect(published.lastPathComponent == "pet-animation.mp4")
    #expect(published.deletingLastPathComponent() == root)
    #expect(try Data(contentsOf: published) == movie)

    // A later copy replaces the same name, so publishing never accumulates exports.
    let replaced = Data([0x03])
    #expect(PetShareClipboard.publishForPasteboard(replaced, named: "pet-animation.mp4", in: root) == published)
    #expect(try Data(contentsOf: published) == replaced)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)

    try FileManager.default.removeItem(at: root)
}
