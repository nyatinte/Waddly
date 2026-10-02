import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
import WaddlyCore

@Test func rejectsInvalidPngData() {
    let invalidData = Data("not a PNG".utf8)

    #expect(PetSpriteSheetImporter.frames(from: invalidData) == nil)
    #expect(PetSpriteSheetImporter.image(from: invalidData) == nil)
    #expect(PetSpriteSheetImporter.optimizedImage(from: invalidData) == nil)
}

@Test func importsTransparentSpriteSheetIntoPetCategories() throws {
    let data = try #require(makePNG(width: 6, height: 6))
    let images = try #require(PetSpriteSheetImporter.frames(from: data))

    #expect(images[.idle].count == 2)
    #expect(images[.typing].count == 4)
    #expect(images[.sleep].count == 2)
    #expect(images[.enter].count == 1)
    #expect(images.isComplete)
    #expect(images[.idle][0].size == NSSize(width: 2, height: 2))
    #expect(PetSpriteSheetImporter.image(from: data) != nil)
    #expect(!PetImageSet().isComplete)
}

@Test func rejectsInvalidSpriteSheetDimensionsAndOpaqueImages() throws {
    let rectangle = try #require(makePNG(width: 6, height: 3))
    let opaque = try #require(makePNG(width: 6, height: 6, alphaInfo: .noneSkipLast))

    #expect(PetSpriteSheetImporter.frames(from: rectangle) == nil)
    #expect(PetSpriteSheetImporter.frames(from: opaque) == nil)
    #expect(PetSpriteSheetImporter.optimizedImage(from: opaque) == nil)
}

@Test func rejectsValidPngDataLargerThanTheFileLimit() throws {
    let data = try #require(makeLargePNG(width: 3072, height: 3072))

    #expect(data.count > PetSpriteSheetImporter.maximumFileSize)
    #expect(PetSpriteSheetImporter.frames(from: data) == nil)
    #expect(PetSpriteSheetImporter.optimizedImage(from: data) == nil)
}

@Test func downsamplesLargePngsToTheConfiguredMaximum() throws {
    let data = try #require(makePNG(width: 2048, height: 2048))
    let optimized = try #require(PetSpriteSheetImporter.optimizedImage(from: data))
    let source = try #require(CGImageSourceCreateWithData(optimized.pngData as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
    let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)

    #expect(optimized.wasDownsampled)
    #expect(width == PetSpriteSheetImporter.maximumImageDimension)
    #expect(height == PetSpriteSheetImporter.maximumImageDimension)
    #expect(optimized.image.size == NSSize(width: 1024, height: 1024))
}

@Test func importsAndPersistsTheExampleSpriteSheet() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "nyatinte-bot-3x3",
            withExtension: "png",
            subdirectory: "Fixtures"
        )
    )
    let data = try Data(contentsOf: fixtureURL)
    let images = try #require(PetSpriteSheetImporter.frames(from: data))

    #expect(images[.idle].count == 2)
    #expect(images[.typing].count == 4)
    #expect(images[.sleep].count == 2)
    #expect(images[.enter].count == 1)

    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WaddlyTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let savedFile = temporaryDirectory.appendingPathComponent("nyatinte-bot-3x3.png")
    try PetSpriteSheetImporter.save(data, to: savedFile)

    #expect(FileManager.default.fileExists(atPath: savedFile.path))
    #expect(PetSpriteSheetImporter.load(from: savedFile) != nil)
}

private func makeLargePNG(width: Int, height: Int) -> Data? {
    let bytesPerRow = width * 4
    let pixelBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerRow * height)
    defer { pixelBytes.deallocate() }

    var state: UInt32 = 0xA5A5_1234
    for offset in stride(from: 0, to: bytesPerRow * height, by: 4) {
        for channel in 0 ..< 3 {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            pixelBytes[offset + channel] = UInt8(truncatingIfNeeded: state)
        }
        pixelBytes[offset + 3] = 255
    }

    guard let context = CGContext(
        data: UnsafeMutableRawPointer(pixelBytes),
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let image = context.makeImage() else {
        return nil
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}

private func makePNG(
    width: Int,
    height: Int,
    alphaInfo: CGImageAlphaInfo = .premultipliedLast
) -> Data? {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: alphaInfo.rawValue
    ), let image = context.makeImage() else {
        return nil
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}
