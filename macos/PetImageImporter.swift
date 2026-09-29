import AppKit
import ImageIO
import UniformTypeIdentifiers

func localizedString(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum PetPhase: Equatable {
    case typing
    case idle
    case sleeping
    case frozen

    static func after(_ seconds: TimeInterval) -> PetPhase {
        let elapsed = max(0, seconds)
        if elapsed < 2.5 { return .typing }
        if elapsed < 25 { return .idle }
        if elapsed < 325 { return .sleeping }
        return .frozen
    }
}

enum TypingMotion: Int, CaseIterable {
    case off
    case weak
    case strong

    var title: String {
        switch self {
        case .off: localizedString("motion.off")
        case .weak: localizedString("motion.weak")
        case .strong: localizedString("motion.strong")
        }
    }

    var amplitude: CGFloat {
        switch self {
        case .off: 0
        case .weak: 5
        case .strong: 10
        }
    }
}

enum PetImageCategory: String, CaseIterable {
    case idle
    case typing
    case sleep
    case enter

    var title: String { localizedString("images.category.\(rawValue)") }
}

struct PetImageSet {
    private var images: [PetImageCategory: [NSImage]]

    init(_ images: [PetImageCategory: [NSImage]] = [:]) {
        self.images = images
    }

    subscript(_ category: PetImageCategory) -> [NSImage] {
        get { images[category] ?? [] }
        set { images[category] = newValue }
    }

    static func bundled(from images: [NSImage]) -> PetImageSet? {
        guard images.count == 16 else { return nil }
        return PetImageSet([
            .idle: [images[0], images[1]],
            .typing: [images[4], images[5], images[6], images[7], images[8], images[9], images[11]],
            .sleep: [images[12], images[13]],
            .enter: [images[10], images[14], images[15]]
        ])
    }
}

func moving<Element>(_ elements: [Element], from source: Int, to destination: Int) -> [Element]? {
    guard elements.indices.contains(source), elements.indices.contains(destination) else { return nil }
    var result = elements
    let item = result.remove(at: source)
    result.insert(item, at: destination)
    return result
}

struct OptimizedPetImage {
    let image: NSImage
    let pngData: Data
    let wasDownsampled: Bool
}

enum PetSpriteSheetImporter {
    static let maximumFileSize = 20 * 1_024 * 1_024
    static let maximumImageDimension = 1_024

    static func optimizedImage(from data: Data) -> OptimizedPetImage? {
        guard data.count <= maximumFileSize,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              sourceType as String == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4_096, height <= 4_096,
              let cgImage = image(from: source, maxDimension: maximumImageDimension) else {
            return nil
        }

        guard hasAlpha(cgImage) else { return nil }
        let wasDownsampled = max(width, height) > maximumImageDimension
        guard let pngData = wasDownsampled ? pngData(from: cgImage) : data,
              pngData.count <= maximumFileSize else { return nil }
        return OptimizedPetImage(
            image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)),
            pngData: pngData,
            wasDownsampled: wasDownsampled
        )
    }

    static func image(from data: Data) -> NSImage? {
        optimizedImage(from: data)?.image
    }

    static func frames(from data: Data) -> PetImageSet? {
        guard data.count <= maximumFileSize,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              sourceType as String == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == height, width % 3 == 0, width <= 4_096,
              let image = image(from: source, maxDimension: maximumImageDimension * 3),
              hasAlpha(image) else {
            return nil
        }

        let cellSize = image.width / 3
        let pointSize = CGFloat(cellSize)
        var cells: [NSImage] = []
        for row in 0..<3 {
            for column in 0..<3 {
                let rect = CGRect(
                    x: CGFloat(column * cellSize),
                    y: CGFloat(row * cellSize),
                    width: pointSize,
                    height: pointSize
                )
                guard let cell = image.cropping(to: rect) else { return nil }
                cells.append(NSImage(cgImage: cell, size: NSSize(width: pointSize, height: pointSize)))
            }
        }
        return PetImageSet([
            .idle: [cells[0], cells[1]],
            .typing: [cells[2], cells[3], cells[4], cells[5]],
            .sleep: [cells[7], cells[8]],
            .enter: [cells[6]]
        ])
    }

    static func load(from url: URL) -> NSImage? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= maximumFileSize,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let optimized = optimizedImage(from: data) else { return nil }
        if optimized.wasDownsampled { try? optimized.pngData.write(to: url, options: .atomic) }
        return optimized.image
    }

    static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            true
        default:
            false
        }
    }

    private static func image(from source: CGImageSource, maxDimension: Int) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        guard max(width, height) > maxDimension else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: false
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func save(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
