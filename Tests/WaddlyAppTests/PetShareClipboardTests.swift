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
    #expect(PetShareClipboard.copyMovie(movie, to: pasteboard))
    #expect(pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier)) == movie)
}
