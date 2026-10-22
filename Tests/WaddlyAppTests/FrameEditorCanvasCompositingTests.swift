import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Pixel checks for the precision canvas foreground compositing.
@Suite(.serialized) @MainActor struct FrameEditorCanvasCompositingTests {
    /// A translucent sprite must be composited once over the clean preview checkerboard, matching
    /// After/export, not once over the dimmed context and again as the foreground.
    @Test func translucentContentIsCompositedOnceAtZeroAndNonzeroOffsets() throws {
        let source = try makeTranslucentSource()
        let background = try canvasPixel(source: nil, offsetX: 0, offsetY: 0)
        let expected = blend(red: 255, green: 0, blue: 0, alpha: 0.5, over: background)

        for (offsetX, offsetY) in [(0, 0), (5, 0), (0, -5), (-7, 3), (5, 5)] {
            let actual = try canvasPixel(source: source, offsetX: offsetX, offsetY: offsetY)
            #expect(
                abs(actual.red - expected.red) <= 4,
                "offset \(offsetX)x\(offsetY): \(actual) vs \(expected)"
            )
            #expect(abs(actual.green - expected.green) <= 4, "green at offset \(offsetX)x\(offsetY)")
            #expect(abs(actual.blue - expected.blue) <= 4, "blue at offset \(offsetX)x\(offsetY)")
        }
    }

    private func makeTranslucentSource() throws -> CGImage {
        let side = 20
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setBlendMode(.copy)
        try context.setFillColor(#require(CGColor(colorSpace: space, components: [1, 0, 0, 0.5])))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return try #require(context.makeImage())
    }

    private func canvasPixel(source: CGImage?, offsetX: Int, offsetY: Int) throws -> Pixel {
        let view = FrameCanvasNSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        view.appearance = NSAppearance(named: .aqua)
        view.apply(FrameCanvasConfiguration(
            source: source,
            sourceSide: 20,
            canvasSide: 20,
            nominalCell: SquareCrop(x: 0, y: 0, size: 20),
            adjustment: FrameAdjustment(
                crop: SquareCrop(x: 0, y: 0, size: 20),
                offsetX: offsetX,
                offsetY: offsetY
            ),
            tool: .crop,
            zoomPercent: 100,
            showsGrid: false,
            showsCrosshair: false,
            showsWarning: false
        ))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 300,
            pixelsHigh: 300,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let graphics = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        view.cacheDisplay(in: view.bounds, to: bitmap)
        NSGraphicsContext.restoreGraphicsState()

        let color = try #require(bitmap.colorAt(x: 150, y: 150)?.usingColorSpace(.sRGB))
        return Pixel(
            red: Int((color.redComponent * 255).rounded()),
            green: Int((color.greenComponent * 255).rounded()),
            blue: Int((color.blueComponent * 255).rounded())
        )
    }

    private func blend(red: Int, green: Int, blue: Int, alpha: Double, over background: Pixel) -> Pixel {
        Pixel(
            red: Int((Double(red) * alpha + Double(background.red) * (1 - alpha)).rounded()),
            green: Int((Double(green) * alpha + Double(background.green) * (1 - alpha)).rounded()),
            blue: Int((Double(blue) * alpha + Double(background.blue) * (1 - alpha)).rounded())
        )
    }

    private struct Pixel {
        let red: Int
        let green: Int
        let blue: Int
    }
}
