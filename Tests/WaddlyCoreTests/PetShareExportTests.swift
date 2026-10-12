import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import Testing
import UniformTypeIdentifiers
import WaddlyCore

@Test func shareMovieExportsFiveSecondsOfThePetAnimation() async throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "nyatinte-bot-3x3",
            withExtension: "png",
            subdirectory: "Fixtures"
        )
    )
    let images = try #require(PetSpriteSheetImporter.frames(from: Data(contentsOf: fixtureURL)))
    let movieURL = FileManager.default.temporaryDirectory.appendingPathComponent("Waddly-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: movieURL) }

    try PetShareExporter.writeMovie(from: images, to: movieURL)
    let asset = AVURLAsset(url: movieURL)
    let duration = try await asset.load(.duration)
    let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let size = try await videoTrack.load(.naturalSize)

    #expect(abs(CMTimeGetSeconds(duration) - 5) < 0.1)
    #expect(size == CGSize(width: 384, height: 384))
}

@Test func shareSpriteSheetExportsTheCanonicalNineFramesAsTransparentPNG() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "nyatinte-bot-3x3",
            withExtension: "png",
            subdirectory: "Fixtures"
        )
    )
    let images = try #require(PetSpriteSheetImporter.frames(from: Data(contentsOf: fixtureURL)))
    let png = try #require(PetShareExporter.spriteSheetPNG(from: images))
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
    let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
    let exported = try #require(PetSpriteSheetImporter.frames(from: png))

    #expect(width == 768)
    #expect(height == 768)
    #expect(exported.isComplete)
    #expect(exported[.idle].count == 2)
    #expect(exported[.typing].count == 4)
    #expect(exported[.enter].count == 1)
    #expect(exported[.sleep].count == 2)
    for category in PetImageCategory.allCases {
        for index in images[category].indices {
            #expect(try rgbaSHA256(exported[category][index]) == rgbaSHA256(images[category][index]))
        }
    }
}

private func rgbaSHA256(_ image: NSImage) throws -> String {
    let raster = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let bytesPerRow = raster.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * raster.height)
    return try pixels.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(
            data: buffer.baseAddress,
            width: raster.width,
            height: raster.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(raster, in: CGRect(x: 0, y: 0, width: raster.width, height: raster.height))
        return SHA256.hash(data: Data(buffer)).map { String(format: "%02x", $0) }.joined()
    }
}
