import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct FrameEditorCanvasInteractionTests {
    @Test func draggingTheBackgroundPansTheViewportWithoutChangingTheCrop() throws {
        let view = FrameCanvasNSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        var adjustments: [FrameAdjustment] = []
        view.onAdjustmentChange = { adjustments.append($0) }
        try view.apply(FrameCanvasConfiguration(
            source: makeImage(),
            sourceSide: 20,
            canvasSide: 20,
            nominalCell: SquareCrop(x: 0, y: 0, size: 20),
            adjustment: FrameAdjustment(crop: SquareCrop(x: 0, y: 0, size: 20), offsetX: 0, offsetY: 0),
            tool: .crop,
            zoomScale: 1,
            showsGrid: false,
            showsCrosshair: false,
            showsWarning: false
        ))
        view.layoutSubtreeIfNeeded()

        try view.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 10, y: 10)))
        try view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 70, y: 45)))
        try view.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 70, y: 45)))

        #expect(view.panOffset.x == 60)
        #expect(abs(view.panOffset.y) == 35)
        #expect(adjustments.isEmpty)
    }

    private func makeImage() throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: 20,
            height: 20,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        try context.setFillColor(#require(CGColor(colorSpace: space, components: [1, 0, 0, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        return try #require(context.makeImage())
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
