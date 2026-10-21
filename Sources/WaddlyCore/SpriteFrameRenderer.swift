import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Crops and aligns one frame from a sprite sheet.
///
/// The renderer is pixel-exact: every draw is nearest-neighbor, content outside the crop is never
/// sampled, and alignment padding is fully transparent. Source and output coordinates are top-left
/// based with +Y down; the renderer converts to Core Graphics' bottom-left space internally.
public enum SpriteFrameRenderer {
    /// Renders `adjustment.crop` from `source` as a square image.
    ///
    /// - Parameter cappedOutputSide: when positive and smaller than the crop size, the output is
    ///   scaled down to this side with nearest-neighbor sampling, which keeps live drag previews
    ///   cheap. `nil` or a larger value renders at the crop's natural size.
    public static func render(
        source: CGImage,
        adjustment: FrameAdjustment,
        cappedOutputSide: Int? = nil
    ) -> CGImage? {
        let cropSide = adjustment.crop.size
        guard cropSide > 0, source.width > 0, source.height > 0 else { return nil }
        let outputSide = cappedOutputSide.flatMap { $0 > 0 && $0 < cropSide ? $0 : nil } ?? cropSide
        let scale = CGFloat(outputSide) / CGFloat(cropSide)
        let offset = scaledOffset(adjustment: adjustment, scale: scale)
        let space = source.colorSpace?.model == .rgb ? source.colorSpace : CGColorSpaceCreateDeviceRGB()
        guard let space, let context = CGContext(
            data: nil,
            width: outputSide,
            height: outputSide,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        // Only the crop's projected area is visible; the rest of `source` is clipped away.
        context.clip(to: CGRect(
            x: CGFloat(offset.x),
            y: CGFloat(-offset.y),
            width: CGFloat(outputSide),
            height: CGFloat(outputSide)
        ))
        context.draw(source, in: destination(
            source: source,
            crop: adjustment.crop,
            offset: offset,
            scale: scale,
            outputSide: outputSide
        ))
        return context.makeImage()
    }

    public static func renderNSImage(
        source: CGImage,
        adjustment: FrameAdjustment,
        cappedOutputSide: Int? = nil
    ) -> NSImage? {
        guard let image = render(
            source: source,
            adjustment: adjustment,
            cappedOutputSide: cappedOutputSide
        ) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// Renders `adjustment.crop` into a fixed square canvas as a 1:1 window.
    ///
    /// The crop's pixels are never scaled: they are drawn centred in the canvas and then shifted by
    /// the alignment offset, so a centred crop-size change only narrows what is visible while every
    /// source pixel keeps the same canvas coordinate. Content outside the crop is transparent and
    /// the crop is clipped to the canvas bounds, so all frames share one output dimension.
    ///
    /// - Parameter cappedOutputSide: when positive and smaller than `canvasSide`, the whole canvas is
    ///   scaled down with nearest-neighbor sampling for cheap live previews. `nil` or a larger value
    ///   keeps the natural `canvasSide` square.
    public static func renderCanvas(
        source: CGImage,
        adjustment: FrameAdjustment,
        canvasSide: Int,
        cappedOutputSide: Int? = nil
    ) -> CGImage? {
        let crop = adjustment.crop
        guard canvasSide > 0, crop.size > 0, source.width > 0, source.height > 0 else { return nil }
        let outputSide = cappedOutputSide.flatMap { $0 > 0 && $0 < canvasSide ? $0 : nil } ?? canvasSide
        let scale = CGFloat(outputSide) / CGFloat(canvasSide)
        let contentSide = CGFloat(crop.size) * scale
        let originX = canvasOrigin(
            canvasSide: canvasSide,
            offset: adjustment.offsetX,
            cropSide: crop.size,
            scale: scale
        )
        let originY = canvasOrigin(
            canvasSide: canvasSide,
            offset: adjustment.offsetY,
            cropSide: crop.size,
            scale: scale
        )
        let space = source.colorSpace?.model == .rgb ? source.colorSpace : CGColorSpaceCreateDeviceRGB()
        guard let space, let context = CGContext(
            data: nil,
            width: outputSide,
            height: outputSide,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        // Only the crop's projected area is visible; the rest of `source` is clipped away.
        context.clip(to: CGRect(
            x: CGFloat(originX),
            y: CGFloat(outputSide) - CGFloat(originY) - contentSide,
            width: contentSide,
            height: contentSide
        ))
        let width = CGFloat(source.width) * scale
        let height = CGFloat(source.height) * scale
        let top = CGFloat(originY) - CGFloat(crop.y) * scale
        context.draw(source, in: CGRect(
            x: CGFloat(originX) - CGFloat(crop.x) * scale,
            y: CGFloat(outputSide) - top - height,
            width: width,
            height: height
        ))
        return context.makeImage()
    }

    public static func renderCanvasNSImage(
        source: CGImage,
        adjustment: FrameAdjustment,
        canvasSide: Int,
        cappedOutputSide: Int? = nil
    ) -> NSImage? {
        guard let image = renderCanvas(
            source: source,
            adjustment: adjustment,
            canvasSide: canvasSide,
            cappedOutputSide: cappedOutputSide
        ) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// The canvas origin of the crop's top-left corner in top-left UI coordinates.
    ///
    /// Double math keeps odd canvas/crop parities consistent, and the final rounding is the only
    /// place the fractional centre becomes a pixel.
    private static func canvasOrigin(
        canvasSide: Int,
        offset: Int,
        cropSide: Int,
        scale: CGFloat
    ) -> Int {
        let centered = CGFloat(canvasSide) / 2 + CGFloat(offset) - CGFloat(cropSide) / 2
        return Int((centered * scale).rounded())
    }

    /// Scales `source` into a `side` by `side` nearest-neighbor preview.
    public static func thumbnail(source: CGImage, side: Int) -> NSImage? {
        guard side > 0, source.width > 0, source.height > 0 else { return nil }
        let space = source.colorSpace?.model == .rgb ? source.colorSpace : CGColorSpaceCreateDeviceRGB()
        guard let space, let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: side, height: side))
    }

    private static func scaledOffset(adjustment: FrameAdjustment, scale: CGFloat) -> (x: Int, y: Int) {
        (
            x: Int((CGFloat(adjustment.offsetX) * scale).rounded()),
            y: Int((CGFloat(adjustment.offsetY) * scale).rounded())
        )
    }

    /// The rect that draws the whole source so its top-left lands at the alignment offset.
    private static func destination(
        source: CGImage,
        crop: SquareCrop,
        offset: (x: Int, y: Int),
        scale: CGFloat,
        outputSide: Int
    ) -> CGRect {
        let width = CGFloat(source.width) * scale
        let height = CGFloat(source.height) * scale
        // Top-left UI coordinates become Core Graphics' bottom-left ones.
        let top = CGFloat(offset.y) - CGFloat(crop.y) * scale
        return CGRect(
            x: CGFloat(offset.x) - CGFloat(crop.x) * scale,
            y: CGFloat(outputSide) - top - height,
            width: width,
            height: height
        )
    }
}

/// Decodes the stored sheet PNG back into a `CGImage` without re-encoding it.
public enum PetFrameSourceDecoder {
    public static func sheetImage(from pngData: Data) -> CGImage? {
        guard !pngData.isEmpty,
              let source = CGImageSourceCreateWithData(
                  pngData as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              CGImageSourceGetType(source) as String? == UTType.png.identifier
        else { return nil }
        return CGImageSourceCreateImageAtIndex(
            source,
            0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        )
    }

    /// The raster behind a loaded frame image, for individual-frame editing sources.
    public static func frameImage(from image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
