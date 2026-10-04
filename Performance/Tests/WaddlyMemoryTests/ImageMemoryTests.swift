import AppKit
import MemoryAllocation
import Testing
import TestingPerformance
import WaddlyCore

@Suite(.serialized)
final class ImageMemoryTests {
    let source: Data

    init() throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 3072,
            pixelsHigh: 3072,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let pixels = try #require(bitmap.bitmapData)
        for index in 0 ..< bitmap.bytesPerRow * bitmap.pixelsHigh {
            pixels[index] = UInt8(truncatingIfNeeded: index / 17)
        }
        source = try #require(bitmap.representation(using: .png, properties: [:]))
        // Warm ImageIO/AppKit caches before process-wide allocation measurement.
        try autoreleasepool {
            let images = try #require(PetSpriteSheetImporter.frames(from: source))
            _ = try #require(PetSpriteSheetImporter.pngData(for: images[.typing][0]))
        }
    }

    @Test(.trackPeakMemory(limit: 2_000_000))
    func repeatedSpriteImportAndPersistence() throws {
        try runImports()
    }

    @Test(.timed(iterations: 3, detectLeaks: true))
    func repeatedImportsReleaseAllocations() throws {
        try runImports()
    }

    private func runImports() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let peak = PeakMemoryTracker()
        for _ in 0 ..< 2 {
            try autoreleasepool {
                let images = try #require(PetSpriteSheetImporter.frames(from: source))
                peak.sample()
                for category in PetImageCategory.allCases {
                    for (index, image) in images[category].enumerated() {
                        let data = try #require(PetSpriteSheetImporter.pngData(for: image))
                        let url = directory.appendingPathComponent("\(category.rawValue)-\(index).png")
                        try PetSpriteSheetImporter.save(data, to: url)
                        let loaded = try #require(PetSpriteSheetImporter.load(from: url))
                        peak.sample()
                        withExtendedLifetime(loaded) {}
                    }
                }
            }
        }
        print("Image pipeline sampled live-byte peak: \(peak.peakBytes) bytes")
        #expect(peak.peakBytes < 2_000_000)
    }
}
