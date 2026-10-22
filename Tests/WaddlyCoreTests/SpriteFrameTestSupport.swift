import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
import WaddlyCore

// MARK: - Synthetic sheets

/// One RGBA pixel, channel order R, G, B, A (premultiplied, as Core Graphics stores it).
struct SpriteTestPixel: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    static let clear = SpriteTestPixel(red: 0, green: 0, blue: 0, alpha: 0)

    /// The inverse color, used to tell a cell's top half from its bottom half.
    var inverted: SpriteTestPixel {
        SpriteTestPixel(red: 255 - red, green: 255 - green, blue: 255 - blue, alpha: alpha)
    }
}

/// Distinct opaque colors indexed by sheet cell, so cell 01 is index 0.
let spriteTestCellColors: [SpriteTestPixel] = [
    SpriteTestPixel(red: 255, green: 0, blue: 0, alpha: 255),
    SpriteTestPixel(red: 0, green: 255, blue: 0, alpha: 255),
    SpriteTestPixel(red: 0, green: 0, blue: 255, alpha: 255),
    SpriteTestPixel(red: 255, green: 255, blue: 0, alpha: 255),
    SpriteTestPixel(red: 255, green: 0, blue: 255, alpha: 255),
    SpriteTestPixel(red: 0, green: 255, blue: 255, alpha: 255),
    SpriteTestPixel(red: 255, green: 128, blue: 0, alpha: 255),
    SpriteTestPixel(red: 128, green: 0, blue: 255, alpha: 255),
    SpriteTestPixel(red: 0, green: 128, blue: 128, alpha: 255)
]

/// Builds a top-left-origin RGBA image. Row 0 is the top row, as Core Graphics stores bitmaps.
func spriteTestImage(
    width: Int,
    height: Int,
    pixel: (Int, Int) -> SpriteTestPixel
) -> CGImage? {
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
    var image: CGImage?
    bytes.withUnsafeMutableBytes { raw in
        guard let base = raw.baseAddress else { return }
        for row in 0 ..< height {
            for column in 0 ..< width {
                let value = pixel(column, row)
                let offset = row * bytesPerRow + column * 4
                base.storeBytes(of: value.red, toByteOffset: offset, as: UInt8.self)
                base.storeBytes(of: value.green, toByteOffset: offset + 1, as: UInt8.self)
                base.storeBytes(of: value.blue, toByteOffset: offset + 2, as: UInt8.self)
                base.storeBytes(of: value.alpha, toByteOffset: offset + 3, as: UInt8.self)
            }
        }
        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return }
        image = context.makeImage()
    }
    return image
}

/// A 3×3 sheet where every cell is one solid color from `spriteTestCellColors`.
func spriteTestSolidSheet(cellSize: Int = 20) -> CGImage? {
    spriteTestImage(width: cellSize * 3, height: cellSize * 3) { column, row in
        spriteTestCellColors[(row / cellSize) * 3 + (column / cellSize)]
    }
}

/// A 3×3 sheet whose cells are split horizontally: top half the cell color, bottom half inverted.
func spriteTestOrientedSheet(cellSize: Int = 20) -> CGImage? {
    spriteTestImage(width: cellSize * 3, height: cellSize * 3) { column, row in
        let color = spriteTestCellColors[(row / cellSize) * 3 + (column / cellSize)]
        return (row % cellSize) < cellSize / 2 ? color : color.inverted
    }
}

/// RGBA bytes of `image`, row-major from the top-left.
func spriteTestPixels(of image: CGImage) -> [UInt8] {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
    bytes.withUnsafeMutableBytes { raw in
        guard let context = CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return bytes
}

func spriteTestPixel(_ pixels: [UInt8], column: Int, row: Int, width: Int) -> SpriteTestPixel {
    let offset = (row * width + column) * 4
    return SpriteTestPixel(
        red: pixels[offset],
        green: pixels[offset + 1],
        blue: pixels[offset + 2],
        alpha: pixels[offset + 3]
    )
}

/// A single pixel from a rendered image, in top-left coordinates.
func spriteTestPixel(of image: CGImage, column: Int, row: Int) -> SpriteTestPixel {
    spriteTestPixel(spriteTestPixels(of: image), column: column, row: row, width: image.width)
}

func spriteTestSheetData() -> Data? {
    guard let sheet = spriteTestSolidSheet() else { return nil }
    return spriteTestPNGData(for: sheet)
}

func spriteTestPNGData(for image: CGImage) -> Data? {
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

/// Sheet-mode identity editing for a 3×3 sheet with `cellSize` cells.
func spriteTestSheetEditing(cellSize: Int = 20) -> SpriteFrameEditing {
    SpriteFrameEditing.identity(
        mode: .sheet,
        sourceSides: Array(repeating: cellSize, count: SpriteFrameSlot.allCases.count),
        cellSize: cellSize
    )
}

func spriteTestSheetGeometry(
    cellSize: Int = 20,
    slot: SpriteFrameSlot = .typing3
) -> FrameEditGeometry {
    spriteTestSheetEditing(cellSize: cellSize).geometry(for: slot)
}
