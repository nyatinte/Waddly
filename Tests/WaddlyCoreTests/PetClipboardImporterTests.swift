import AppKit
import Testing
@testable import WaddlyCore

/// The clipboard reader only reads on an explicit paste; these tests cover what each supported
/// clipboard shape produces and that nothing is imported from an unsupported one.
@Suite(.serialized) @MainActor struct PetClipboardImporterTests {
    @Test func anEmptyClipboardOffersNothing() {
        let pasteboard = makePasteboard()
        #expect(!PetClipboardImporter.hasSupportedImage(on: pasteboard))
        #expect(PetClipboardImporter.sheetData(from: pasteboard) == nil)
    }

    @Test func copiedBitmapPixelsAreNormalizedToASheet() throws {
        let pasteboard = makePasteboard()
        #expect(try pasteboard.writeObjects([makeSheetImage()]))
        #expect(PetClipboardImporter.hasSupportedImage(on: pasteboard))
        let data = try #require(PetClipboardImporter.sheetData(from: pasteboard))
        #expect(PetSpriteSheetImporter.frames(from: data) != nil)
    }

    @Test func aCopiedPNGFileIsReadAsItsExactBytes() throws {
        let pasteboard = makePasteboard()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let png = try #require(try PetSpriteSheetImporter.pngData(for: makeSheetImage()))
        try png.write(to: url)
        #expect(pasteboard.writeObjects([url as NSURL]))

        #expect(PetClipboardImporter.hasSupportedImage(on: pasteboard))
        #expect(PetClipboardImporter.sheetData(from: pasteboard) == png)
    }

    @Test func aCopiedNonPNGFileOffersNothing() throws {
        let pasteboard = makePasteboard()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an image".utf8).write(to: url)
        #expect(pasteboard.writeObjects([url as NSURL]))

        #expect(!PetClipboardImporter.hasSupportedImage(on: pasteboard))
        #expect(PetClipboardImporter.sheetData(from: pasteboard) == nil)
    }
}

@MainActor
private func makePasteboard() -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("WaddlyTests.clipboard.\(UUID().uuidString)"))
    pasteboard.clearContents()
    return pasteboard
}

/// A 9×9 transparent PNG, the smallest valid 3×3 sprite sheet.
private func makeSheetImage() throws -> NSImage {
    let context = try #require(CGContext(
        data: nil,
        width: 9,
        height: 9,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let raster = try #require(context.makeImage())
    return NSImage(cgImage: raster, size: NSSize(width: 9, height: 9))
}
