import AppKit
import CryptoKit
import Testing
import WaddlyCore

@Test func spriteSheetExtractionMatchesPixelSnapshots() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "nyatinte-bot-3x3",
            withExtension: "png",
            subdirectory: "Fixtures"
        )
    )
    let data = try Data(contentsOf: fixtureURL)
    let bitmap = try #require(NSBitmapImageRep(data: data))
    // Enter sparkles must not bleed into the left edge of sleep-1.
    for y in 652 ..< 710 {
        for x in 256 ..< 258 {
            #expect(bitmap.colorAt(x: x, y: y)?.alphaComponent == 0)
        }
    }
    let images = try #require(PetSpriteSheetImporter.frames(from: data))

    let snapshots = try PetImageCategory.allCases.flatMap { category in
        try images[category].enumerated().map { index, image in
            try ImageSnapshot(
                name: "\(category.rawValue)-\(index + 1)",
                size: image.size,
                sha256: rgbaSHA256(for: image)
            )
        }
    }

    #expect(snapshots == expectedSpriteSheetSnapshots)

    if ProcessInfo.processInfo.environment["WADDLY_PRINT_SNAPSHOTS"] == "1" {
        print(formatSnapshots(snapshots))
    }
}

private struct ImageSnapshot: Equatable {
    let name: String
    let size: CGSize
    let sha256: String
}

private let expectedSpriteSheetSnapshots: [ImageSnapshot] = [
    snapshot("idle-1", "e382c5b2253a398988ca5f14396e056a5e401491e4bbd1e64a1148a29f6cc98e"),
    snapshot("idle-2", "360d838d39c8d802b2e8b9d76d83affededbbe02ab592b634cc7e037a5f45d14"),
    snapshot("typing-1", "2b76edf2f126480889fbc3a22c0eb76e6fd7cade7387595004867fd8a4e198c8"),
    snapshot("typing-2", "5bdb983904f5709db179f3ea0c59384dc7d9bfccc82d2de62467c0239a249740"),
    snapshot("typing-3", "c838526ead7d9b076923aa1f527b805f021631b5fcbe9bf280d4b71192f6aca6"),
    snapshot("typing-4", "2ad6784ae66ddec577fcd33341d2f6f2c4c1b12b95b77997715bbb2d341d2834"),
    snapshot("sleep-1", "52f3d719ee294a0849dc0a1c009949a866db6b85df4d5cd219f375c5269a2e7d"),
    snapshot("sleep-2", "a18e0fa8341379d221424c2e5f7d36aa74acfc0a412be9f17c1be4cc04ebfcd5"),
    snapshot("enter-1", "fcd7fbf2e72c4ec789d739d3527bd6be7ef2157998303ad975742694c2422b68")
]

private func snapshot(_ name: String, _ sha256: String) -> ImageSnapshot {
    ImageSnapshot(name: name, size: CGSize(width: 256, height: 256), sha256: sha256)
}

private func rgbaSHA256(for image: NSImage) throws -> String {
    let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let bytesPerPixel = 4
    let bytesPerRow = cgImage.width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * cgImage.height)

    return try pixels.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(
            data: buffer.baseAddress,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        return SHA256.hash(data: Data(buffer)).map { String(format: "%02x", $0) }.joined()
    }
}

private func formatSnapshots(_ snapshots: [ImageSnapshot]) -> String {
    let body = snapshots.map {
        "    snapshot(\"\($0.name)\", \"\($0.sha256)\")"
    }.joined(separator: ",\n")
    return "private let expectedSpriteSheetSnapshots: [ImageSnapshot] = [\n\(body)\n]"
}
