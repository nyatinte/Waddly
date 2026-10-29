import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import WaddlyApp
import WaddlyCore

/// The six shipped reference sheets are product data: every one must import as a 3×3 sheet, keep a
/// transparent safety margin inside every cell, show nine distinct poses, and stay at a comparable
/// character scale so the chooser does not lie about what each style looks like.
@Suite(.serialized) @MainActor struct CharacterStyleSampleTests {
    private static let cell = 256
    private static let sheet = 768
    private static let transparentAlphaThreshold: UInt8 = 8
    private static let minimumCellMargin = 16

    @Test(arguments: CharacterStyle.allCases)
    func sampleSheetImportsAsACompleteNineFrameSet(style: CharacterStyle) throws {
        let url = try sampleURL(for: style)
        let candidate = try #require(try? PetSpriteSheetImporter.inspectFile(at: url).get())
        #expect(candidate.sourceDimension == Self.sheet)
        #expect(candidate.cellSize == Self.cell)
        #expect(candidate.images.isComplete)
        #expect(candidate.images.isWithinMemoryBudget)
    }

    @Test(arguments: CharacterStyle.allCases)
    func everyCellKeepsATransparentSafetyMargin(style: CharacterStyle) throws {
        let raster = try raster(of: sampleURL(for: style))
        #expect(raster.width == Self.sheet && raster.height == Self.sheet)
        for index in 0 ..< 9 {
            let box = try contentBox(of: index, in: raster)
            let margins = (
                left: box.minX,
                top: box.minY,
                right: Self.cell - 1 - box.maxX,
                bottom: Self.cell - 1 - box.maxY
            )
            #expect(
                margins.left >= Self.minimumCellMargin
                    && margins.top >= Self.minimumCellMargin
                    && margins.right >= Self.minimumCellMargin
                    && margins.bottom >= Self.minimumCellMargin,
                "cell \(index + 1) margins \(margins)"
            )
        }
        #expect(raster.alpha(column: 0, row: 0) == 0)
        #expect(raster.alpha(column: Self.sheet - 1, row: Self.sheet - 1) == 0)
    }

    @Test(arguments: CharacterStyle.allCases)
    func theNinePosesAreAllDifferent(style: CharacterStyle) throws {
        let raster = try raster(of: sampleURL(for: style))
        var hashes: Set<UInt64> = []
        for index in 0 ..< 9 {
            hashes.insert(hash(ofCellAt: index, in: raster))
        }
        #expect(hashes.count == 9)
    }

    @Test func stylesKeepAComparableCharacterScale() throws {
        var idleHeights: [CharacterStyle: Int] = [:]
        for style in CharacterStyle.allCases {
            let raster = try raster(of: sampleURL(for: style))
            let box = try contentBox(of: 0, in: raster)
            idleHeights[style] = box.height
        }
        let heights = idleHeights.values.sorted()
        // Six styles give an even count: average the two middle heights instead of picking one,
        // so the documented median is the real median.
        let median = heights.count.isMultiple(of: 2)
            ? (heights[heights.count / 2 - 1] + heights[heights.count / 2]) / 2
            : heights[heights.count / 2]
        for (style, height) in idleHeights {
            #expect(
                abs(height - median) <= median * 30 / 100,
                "\(style.rawValue) idle height \(height) vs median \(median)"
            )
        }
    }

    // MARK: - Fixtures

    private func sampleURL(for style: CharacterStyle) throws -> URL {
        SetupWizardFixture.root().appendingPathComponent("assets/character-styles/\(style.rawValue).png")
    }

    private struct Raster {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        func alpha(column: Int, row: Int) -> UInt8 {
            pixels[(row * width + column) * 4 + 3]
        }
    }

    private struct CellBox {
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
        var width: Int {
            maxX - minX + 1
        }

        var height: Int {
            maxY - minY + 1
        }
    }

    private func raster(of url: URL) throws -> Raster {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        // The context holds the buffer only while it draws, so scope the pointer to the draw call
        // instead of handing it an `inout` array that outlives the context.
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard didDraw else { throw FixtureError.unreadableImage }
        return Raster(width: image.width, height: image.height, pixels: pixels)
    }

    private func contentBox(of cellIndex: Int, in raster: Raster) throws -> CellBox {
        let originX = (cellIndex % 3) * Self.cell
        let originY = (cellIndex / 3) * Self.cell
        var minX = Self.cell
        var minY = Self.cell
        var maxX = -1
        var maxY = -1
        for row in 0 ..< Self.cell {
            for column in 0 ..< Self.cell {
                guard raster.alpha(column: originX + column, row: originY + row)
                    > Self.transparentAlphaThreshold
                else {
                    continue
                }
                minX = min(minX, column)
                minY = min(minY, row)
                maxX = max(maxX, column)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= 0, maxY >= 0 else { throw FixtureError.emptyCell }
        return CellBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private func hash(ofCellAt cellIndex: Int, in raster: Raster) -> UInt64 {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325
        let originX = (cellIndex % 3) * Self.cell
        let originY = (cellIndex / 3) * Self.cell
        for row in 0 ..< Self.cell {
            for column in 0 ..< Self.cell {
                let pixel = (originY + row) * raster.width + originX + column
                for channel in 0 ..< 4 {
                    value = (value ^ UInt64(raster.pixels[pixel * 4 + channel])) &* 0x0000_0100_0000_01B3
                }
            }
        }
        return value
    }

    private enum FixtureError: Error {
        case emptyCell
        case unreadableImage
    }
}
