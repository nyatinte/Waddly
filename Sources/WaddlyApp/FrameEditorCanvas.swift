import AppKit
import SwiftUI
import WaddlyCore

/// Everything the canvas needs to render one selected frame. Kept value-typed so SwiftUI can tell
/// whether a redraw is necessary.
struct FrameCanvasConfiguration {
    var source: CGImage?
    var sourceSide: Int
    var canvasSide: Int = 0
    var nominalCell: SquareCrop?
    var adjustment: FrameAdjustment
    var tool: FrameEditorTool
    var zoomScale: CGFloat = 1
    /// Changes when the selected frame changes, so the viewport pan resets.
    var resetKey: Int = 0
    var showsGrid: Bool
    var showsCrosshair: Bool
    var showsWarning: Bool
    var accessibilityLabel: String = ""
    var accessibilityValue: String = ""
    var accessibilityHelp: String = ""
    var zoomInLabel: String = ""
    var zoomOutLabel: String = ""
    var resetViewLabel: String = ""
}

/// A precision crop canvas with eight square-locked resize handles, dimmed surroundings, rule-of-
/// thirds guides and a marked center crosshair. It draws the source pixels nearest-neighbor.
struct FrameEditorCanvas: NSViewRepresentable {
    let configuration: FrameCanvasConfiguration
    let onAdjustmentChange: (FrameAdjustment) -> Void
    let onZoomChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> FrameCanvasNSView {
        let view = FrameCanvasNSView(frame: .zero)
        view.onAdjustmentChange = onAdjustmentChange
        view.onZoomChange = onZoomChange
        view.apply(configuration)
        return view
    }

    func updateNSView(_ view: FrameCanvasNSView, context: Context) {
        view.onAdjustmentChange = onAdjustmentChange
        view.onZoomChange = onZoomChange
        view.apply(configuration)
    }

    /// The canvas holds the decoded sheet and the model callback. SwiftUI tears the representable
    /// down when the editor sheet goes away; drop those references immediately instead of waiting
    /// for the hosting view's deallocation.
    static func dismantleNSView(_ view: FrameCanvasNSView, coordinator: ()) {
        view.releaseResources()
    }
}

final class FrameCanvasNSView: NSView {
    var onAdjustmentChange: ((FrameAdjustment) -> Void)?
    var onZoomChange: ((CGFloat) -> Void)?
    /// Viewport translation in view points, driven by background drags and scrolling.
    var panOffset = CGPoint.zero
    private var lastResetKey: Int?

    var configuration: FrameCanvasConfiguration?
    var trackingAreaReference: NSTrackingArea?
    var drag: DragState?

    enum DragTarget {
        case handle(SpriteCropHandle)
        case moveCrop
        case alignContent
        case pan
    }

    struct DragState {
        let target: DragTarget
        let startAdjustment: FrameAdjustment
        let startPoint: NSPoint
        let scale: CGFloat
        let startPanOffset: CGPoint
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func apply(_ configuration: FrameCanvasConfiguration) {
        if lastResetKey != configuration.resetKey {
            lastResetKey = configuration.resetKey
            panOffset = .zero
        }
        self.configuration = configuration
        updateAccessibility(configuration)
        needsDisplay = true
    }

    /// Drops the decoded source and callbacks while the editor surface is not alive.
    func releaseResources() {
        configuration = nil
        onAdjustmentChange = nil
        onZoomChange = nil
        drag = nil
        panOffset = .zero
        setAccessibilityElement(false)
    }
}
