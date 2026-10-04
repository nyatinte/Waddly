import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum PetImageCategory: String, CaseIterable, Sendable {
    case idle
    case typing
    case sleep
    case enter
}

public struct PetImageSet: Sendable {
    private var images: [PetImageCategory: [NSImage]]

    public init(_ images: [PetImageCategory: [NSImage]] = [:]) {
        self.images = images
    }

    public subscript(_ category: PetImageCategory) -> [NSImage] {
        get { images[category] ?? [] }
        set { images[category] = newValue }
    }

    /// 40 MiB leaves room for the app, a replacement sheet, and its thumbnail.
    public static let maximumResidentBytes = 40 * 1024 * 1024

    public var estimatedResidentBytes: Int {
        var cost = 0
        for category in PetImageCategory.allCases {
            for image in self[category] {
                guard let raster = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      raster.height > 0, raster.bytesPerRow <= Self.maximumResidentBytes / raster.height
                else {
                    return Self.maximumResidentBytes + 1
                }
                cost += raster.bytesPerRow * raster.height + 128 * 1024
                if cost > Self.maximumResidentBytes {
                    return cost
                }
            }
        }
        return cost
    }

    public var isWithinMemoryBudget: Bool {
        estimatedResidentBytes <= Self.maximumResidentBytes
    }

    public var isComplete: Bool {
        PetImageCategory.allCases.allSatisfy { !self[$0].isEmpty }
    }
}

public struct OptimizedPetImage: Sendable {
    public let image: NSImage
    public let pngData: Data
    public let wasDownsampled: Bool
}

public enum PetSpriteSheetImporter {
    public static let maximumFileSize = 20 * 1024 * 1024
    public static let maximumImageDimension = 1024

    public static func optimizedImage(from data: Data) -> OptimizedPetImage? {
        guard data.count <= maximumFileSize,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let sourceType = CGImageSourceGetType(source),
              sourceType as String == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              let cgImage = image(from: source, maxDimension: maximumImageDimension)
        else {
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

    public static func preview(from data: Data) -> NSImage? {
        guard data.count <= maximumFileSize,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let cgImage = image(from: source, maxDimension: 480), hasAlpha(cgImage) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    public static func readPNG(from url: URL) -> Data? {
        guard url.pathExtension.lowercased() == "png",
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= maximumFileSize else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    public static func image(from data: Data) -> NSImage? {
        optimizedImage(from: data)?.image
    }

    public static func frames(from data: Data) -> PetImageSet? {
        guard data.count <= maximumFileSize,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let sourceType = CGImageSourceGetType(source),
              sourceType as String == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == height, width % 3 == 0, width <= 4096,
              let image = image(from: source, maxDimension: maximumImageDimension * 3),
              hasAlpha(image)
        else {
            return nil
        }

        let cellSize = image.width / 3
        let pointSize = CGFloat(cellSize)
        var cells: [NSImage] = []
        for row in 0 ..< 3 {
            for column in 0 ..< 3 {
                let rect = CGRect(
                    x: CGFloat(column * cellSize),
                    y: CGFloat(row * cellSize),
                    width: pointSize,
                    height: pointSize
                )
                guard let cell = image.cropping(to: rect) else { return nil }
                let space = cell.colorSpace?.model == .rgb ? cell.colorSpace : CGColorSpaceCreateDeviceRGB()
                guard let space, let context = CGContext(
                    data: nil, width: cell.width, height: cell.height,
                    bitsPerComponent: cell.bitsPerComponent, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return nil }
                context.setBlendMode(.copy)
                context.draw(cell, in: CGRect(x: 0, y: 0, width: cell.width, height: cell.height))
                guard let raster = context.makeImage() else { return nil }
                cells.append(NSImage(cgImage: raster, size: NSSize(width: pointSize, height: pointSize)))
            }
        }
        return PetImageSet([
            .idle: [cells[0], cells[1]],
            .typing: [cells[2], cells[3], cells[4], cells[5]],
            .sleep: [cells[7], cells[8]],
            .enter: [cells[6]]
        ])
    }

    public static func load(from url: URL) -> NSImage? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= maximumFileSize,
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        guard let optimized = optimizedImage(from: data) else { return nil }
        if optimized.wasDownsampled {
            try? optimized.pngData.write(to: url, options: .atomic)
        }
        return optimized.image
    }

    public static func pngData(for image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return pngData(from: cgImage)
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
            return CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            )
        }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
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

    public static func save(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
