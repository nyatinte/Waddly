import AppKit
import SwiftUI
import WaddlyCore

extension FrameCanvasNSView {
    // MARK: - Geometry

    struct CanvasLayout {
        let contextRect: CGRect
        let scale: CGFloat
        let origin: CGPoint
    }

    func layout(for configuration: FrameCanvasConfiguration) -> CanvasLayout {
        let side = CGFloat(max(1, configuration.sourceSide))
        let sourceRect = CGRect(x: 0, y: 0, width: side, height: side)
        let cellRect = configuration.nominalCell.map {
            CGRect(x: CGFloat($0.x), y: CGFloat($0.y), width: CGFloat($0.size), height: CGFloat($0.size))
        } ?? sourceRect
        // The viewport is deliberately independent of the crop rectangle: cropping narrows the
        // frame over a stationary source image instead of re-fitting (and appearing to move) the
        // artwork on every drag or slider tick.
        let contextMargin = cellRect.width * 0.75
        let context = cellRect.insetBy(dx: -contextMargin, dy: -contextMargin).intersection(sourceRect)
        let margin: CGFloat = 26
        let available = bounds.insetBy(dx: margin, dy: margin)
        let fit = min(available.width / max(context.width, 1), available.height / max(context.height, 1))
        let zoom = CGFloat(configuration.zoomPercent) / 100
        let scale = max(0.01, fit * zoom)
        let origin = CGPoint(
            x: (bounds.width - context.width * scale) / 2 - context.minX * scale,
            y: (bounds.height - context.height * scale) / 2 - context.minY * scale
        )
        return CanvasLayout(contextRect: context, scale: scale, origin: origin)
    }

    private func viewPoint(for source: CGPoint, layout: CanvasLayout) -> NSPoint {
        NSPoint(x: layout.origin.x + source.x * layout.scale, y: layout.origin.y + source.y * layout.scale)
    }

    func viewRect(for source: CGRect, layout: CanvasLayout) -> CGRect {
        CGRect(
            x: layout.origin.x + source.minX * layout.scale,
            y: layout.origin.y + source.minY * layout.scale,
            width: source.width * layout.scale,
            height: source.height * layout.scale
        )
    }

    func cropViewRect(layout: CanvasLayout) -> CGRect {
        guard let configuration else { return .zero }
        return viewRect(
            for: CGRect(
                x: CGFloat(configuration.adjustment.crop.x),
                y: CGFloat(configuration.adjustment.crop.y),
                width: CGFloat(configuration.adjustment.crop.size),
                height: CGFloat(configuration.adjustment.crop.size)
            ),
            layout: layout
        )
    }

    func handleCenters(cropRect: CGRect) -> [(SpriteCropHandle, NSPoint)] {
        let midX = cropRect.midX
        let midY = cropRect.midY
        return [
            (.topLeft, NSPoint(x: cropRect.minX, y: cropRect.minY)),
            (.top, NSPoint(x: midX, y: cropRect.minY)),
            (.topRight, NSPoint(x: cropRect.maxX, y: cropRect.minY)),
            (.right, NSPoint(x: cropRect.maxX, y: midY)),
            (.bottomRight, NSPoint(x: cropRect.maxX, y: cropRect.maxY)),
            (.bottom, NSPoint(x: midX, y: cropRect.maxY)),
            (.bottomLeft, NSPoint(x: cropRect.minX, y: cropRect.maxY)),
            (.left, NSPoint(x: cropRect.minX, y: midY))
        ]
    }

    func handle(at point: NSPoint, layout: CanvasLayout) -> SpriteCropHandle? {
        let centers = handleCenters(cropRect: cropViewRect(layout: layout))
        let hitRadius: CGFloat = 10
        return centers.first { center in
            hypot(center.1.x - point.x, center.1.y - point.y) <= hitRadius
        }?.0
    }
}

extension FrameCanvasNSView {
    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current, let configuration else { return }
        drawBackground(in: context)
        guard let source = configuration.source else { return }
        let layout = layout(for: configuration)
        context.imageInterpolation = .none
        let sourceRect = CGRect(
            x: 0,
            y: 0,
            width: configuration.sourceSide,
            height: configuration.sourceSide
        )
        let sourceViewRect = viewRect(for: sourceRect, layout: layout)

        // Dimmed sheet context. It stays at its source coordinates so the crop handles, guides and
        // crosshair remain stable while the selected content moves inside them.
        drawImage(source, in: sourceViewRect, context: context)
        drawDimmingOverContext(in: context)

        // Bright foreground: only the selected source window, translated by the alignment offset.
        // This is exactly the foreground `SpriteFrameRenderer.renderCanvas` exports; neighbouring
        // sheet pixels outside the crop never become visible inside it.
        let cropRect = cropViewRect(layout: layout)
        drawAlignedCrop(
            source,
            sourceViewRect: sourceViewRect,
            cropRect: cropRect,
            configuration: configuration,
            context: context
        )

        if configuration.showsGrid {
            drawGrid(in: cropRect, context: context)
        }
        if configuration.showsCrosshair {
            drawCrosshair(in: cropRect, context: context)
        }
        drawCropBorder(in: cropRect, context: context, warning: configuration.showsWarning)
        drawHandles(in: cropRect, context: context)
    }

    private func drawImage(_ image: CGImage, in rect: CGRect, context: NSGraphicsContext) {
        context.imageInterpolation = .none
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(in: rect)
    }

    /// Draws the crop's own pixels shifted by the alignment offset, clipped to the source crop and
    /// to the fixed output canvas, exactly like the exported frame's foreground.
    private func drawAlignedCrop(
        _ source: CGImage,
        sourceViewRect: CGRect,
        cropRect: CGRect,
        configuration: FrameCanvasConfiguration,
        context: NSGraphicsContext
    ) {
        let scale = configuration.sourceSide > 0
            ? sourceViewRect.width / CGFloat(configuration.sourceSide)
            : 1
        let offset = CGPoint(
            x: CGFloat(configuration.adjustment.offsetX) * scale,
            y: CGFloat(configuration.adjustment.offsetY) * scale
        )
        let outputSide = configuration.canvasSide > 0
            ? configuration.canvasSide
            : (configuration.nominalCell?.size ?? configuration.sourceSide)
        let outputRect = CGRect(
            x: cropRect.midX - CGFloat(outputSide) * scale / 2,
            y: cropRect.midY - CGFloat(outputSide) * scale / 2,
            width: CGFloat(outputSide) * scale,
            height: CGFloat(outputSide) * scale
        )
        // Only the selected source window (shifted by the alignment offset) inside the fixed output
        // canvas is the exported foreground.
        let visibleRect = cropRect.offsetBy(dx: offset.x, dy: offset.y).intersection(outputRect)
        guard !visibleRect.isNull, !visibleRect.isEmpty else { return }

        context.cgContext.saveGState()
        context.cgContext.clip(to: visibleRect)
        // Repaint the preview checkerboard in stationary view coordinates; only the source draw is
        // translated. This keeps the preview background identical for every alignment offset.
        context.cgContext.setBlendMode(.copy)
        drawBackground(in: context)
        context.cgContext.setBlendMode(.normal)
        context.cgContext.translateBy(x: offset.x, y: offset.y)
        drawImage(source, in: sourceViewRect, context: context)
        context.cgContext.restoreGState()
    }

    private func drawBackground(in context: NSGraphicsContext) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base = dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.90, alpha: 1)
        let alternate = dark ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        base.setFill()
        bounds.fill()
        alternate.setFill()
        let tile: CGFloat = 9
        let columns = Int(ceil(bounds.width / tile))
        let rows = Int(ceil(bounds.height / tile))
        for row in 0 ..< rows {
            for column in 0 ..< columns where (row + column).isMultiple(of: 2) {
                CGRect(
                    x: bounds.minX + CGFloat(column) * tile,
                    y: bounds.minY + CGFloat(row) * tile,
                    width: tile,
                    height: tile
                ).fill()
            }
        }
    }

    private func drawDimmingOverContext(in context: NSGraphicsContext) {
        NSColor.black.withAlphaComponent(0.55).setFill()
        bounds.fill()
        context.shouldAntialias = true
    }

    private func drawGrid(in cropRect: CGRect, context: NSGraphicsContext) {
        guard cropRect.width > 24, cropRect.height > 24 else { return }
        let thirds = [1.0 / 3.0, 2.0 / 3.0]
        for fraction in thirds {
            let guideX = cropRect.minX + cropRect.width * fraction
            let guideY = cropRect.minY + cropRect.height * fraction
            drawGuideLine(
                from: NSPoint(x: guideX, y: cropRect.minY),
                to: NSPoint(x: guideX, y: cropRect.maxY)
            )
            drawGuideLine(
                from: NSPoint(x: cropRect.minX, y: guideY),
                to: NSPoint(x: cropRect.maxX, y: guideY)
            )
        }
        context.shouldAntialias = true
    }

    /// A thin dark underlay keeps the guide visible on both pale and dark sprite pixels.
    private func drawGuideLine(from start: NSPoint, to end: NSPoint) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1.4
        path.stroke()
        NSColor.white.withAlphaComponent(0.65).setStroke()
        path.lineWidth = 0.7
        path.stroke()
    }

    private func drawCrosshair(in cropRect: CGRect, context: NSGraphicsContext) {
        let center = NSPoint(x: cropRect.midX, y: cropRect.midY)
        drawGuideLine(from: NSPoint(x: center.x, y: cropRect.minY), to: NSPoint(x: center.x, y: cropRect.maxY))
        drawGuideLine(from: NSPoint(x: cropRect.minX, y: center.y), to: NSPoint(x: cropRect.maxX, y: center.y))
        let ring = NSBezierPath(ovalIn: CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9))
        NSColor.white.setFill()
        ring.fill()
        NSColor.controlAccentColor.setStroke()
        ring.lineWidth = 1.5
        ring.stroke()
        context.shouldAntialias = true
    }

    private func drawCropBorder(in cropRect: CGRect, context: NSGraphicsContext, warning: Bool) {
        let path = NSBezierPath(rect: cropRect.insetBy(dx: 0.75, dy: 0.75))
        (warning ? NSColor.systemOrange : NSColor.controlAccentColor).setStroke()
        path.lineWidth = warning ? 2.5 : 2
        if warning {
            path.setLineDash([6, 4], count: 2, phase: 0)
        }
        path.stroke()
        context.shouldAntialias = true
    }

    private func drawHandles(in cropRect: CGRect, context: NSGraphicsContext) {
        let side: CGFloat = 9
        for (_, center) in handleCenters(cropRect: cropRect) {
            let rect = CGRect(
                x: center.x - side / 2,
                y: center.y - side / 2,
                width: side,
                height: side
            )
            let rounded = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            NSColor.windowBackgroundColor.setFill()
            rounded.fill()
            NSColor.controlAccentColor.setStroke()
            rounded.lineWidth = 1.5
            rounded.stroke()
        }
        context.shouldAntialias = true
    }
}
