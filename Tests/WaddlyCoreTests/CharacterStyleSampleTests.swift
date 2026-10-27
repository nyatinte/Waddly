import AppKit
import ImageIO
import Testing
import WaddlyCore

private let characterStyleSampleNames = [
    "pixel-art", "hand-drawn", "iconic", "retro-cartoon", "anime", "paper-cutout"
]

@Test(arguments: characterStyleSampleNames)
func authoredCharacterSamplesImportWithExactSemanticCrops(style: String) throws {
    // Resolve the shipped artwork, not a copied fixture or a synthetic substitute.
    let repositoryURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = repositoryURL.appendingPathComponent("assets/character-styles/\(style).png")
    let data = try Data(contentsOf: url)
    let candidate = try PetSpriteSheetImporter.inspect(data).get()
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let sheet = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let bitmap = try #require(NSBitmapImageRep(data: data))

    #expect(sheet.width == 768)
    #expect(sheet.height == 768)
    #expect(bitmap.hasAlpha)
    #expect(candidate.sourceDimension == 768)
    #expect(candidate.cellSize == 256)
    #expect(candidate.sheetPNGData == data)
    #expect(candidate.images.isComplete)
    #expect(candidate.images.isWithinMemoryBudget)
    #expect(PetSpriteSheetImporter.preview(from: data) != nil)

    // Canonical row-major cells: idle, blink, focus, type, variation, fast, Enter, drowsy, sleep.
    let categories: [(PetImageCategory, [Int])] = [
        (.idle, [0, 1]), (.typing, [2, 3, 4, 5]), (.enter, [6]), (.sleep, [7, 8])
    ]
    let firstCell = try #require(sheet.cropping(to: CGRect(x: 0, y: 0, width: 256, height: 256)))
    let hat = CGRect(x: 64, y: 64, width: 128, height: 46)
    let feet = CGRect(x: 64, y: 188, width: 128, height: 4)
    let anchoredHat = try characterSampleRegionPixels(firstCell, rect: hat)
    let anchoredFeet = try characterSampleRegionPixels(firstCell, rect: feet)

    for (category, indices) in categories {
        let frames = candidate.images[category]
        try #require(frames.count == indices.count)
        for (frame, index) in zip(frames, indices) {
            let imported = try #require(frame.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let crop = CGRect(x: (index % 3) * 256, y: (index / 3) * 256, width: 256, height: 256)
            let expected = try #require(sheet.cropping(to: crop))
            let pixels = spriteTestPixels(of: imported)

            #expect(frame.size == NSSize(width: 256, height: 256))
            #expect(imported.width == 256)
            #expect(imported.height == 256)
            #expect(pixels == spriteTestPixels(of: expected))
            #expect(characterSampleHasClearMargins(pixels))
            #expect(stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] == 255 })
            #expect(try characterSampleRegionPixels(imported, rect: hat) == anchoredHat)
            #expect(try characterSampleRegionPixels(imported, rect: feet) == anchoredFeet)
        }
    }
}

private func characterSampleRegionPixels(_ image: CGImage, rect: CGRect) throws -> [UInt8] {
    let crop = try #require(image.cropping(to: rect))
    return spriteTestPixels(of: crop)
}

private func characterSampleHasClearMargins(_ pixels: [UInt8]) -> Bool {
    guard pixels.count == 256 * 256 * 4 else { return false }
    for row in 0 ..< 256 {
        for column in 0 ..< 256 where row < 64 || row >= 192 || column < 64 || column >= 192 {
            if pixels[(row * 256 + column) * 4 + 3] != 0 {
                return false
            }
        }
    }
    return true
}
