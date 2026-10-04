import AppKit
import MemoryAllocation
import Testing
import TestingPerformance
import WaddlyCore

@Suite(.serialized, WarmImageMemoryFixture())
final class ImageMemoryTests {
    private static let fixture = Result { try makeSource() }
    let source: Data

    init() throws {
        source = try Self.fixture.get()
    }

    static func prepareFixture() throws {
        // prepare(for:) runs before performance scopes capture their baseline.
        // Reuse a complete import/save/reload to warm every codec path.
        _ = try ImageMemoryTests().runImports()
    }

    private static func makeSource() throws -> Data {
        try autoreleasepool {
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
            return try #require(bitmap.representation(using: .png, properties: [:]))
        }
    }

    @Test(.trackPeakMemory(limit: 64 * 1024 * 1024))
    func repeatedSpriteImportAndPersistence() throws {
        let peak = try runImports()
        #expect(peak < 64 * 1024 * 1024)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WADDLY_EVALUATE_LEAKS"] == "1"),
          .timed(iterations: 3, detectLeaks: true))
    func repeatedImportsReleaseAllocations() throws {
        _ = try runImports()
    }

    private func runImports() throws -> Int {
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
        return peak.peakBytes
    }
}

private struct WarmImageMemoryFixture: SuiteTrait {
    func prepare(for test: Test) async throws {
        try ImageMemoryTests.prepareFixture()
    }
}
