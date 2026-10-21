import AppKit
import SwiftUI
import WaddlyCore

/// Everything the canvas needs to render one selected frame. Kept value-typed so SwiftUI can tell
/// whether a redraw is necessary.
struct FrameCanvasConfiguration {
    var source: CGImage?
    var sourceSide: Int
    var nominalCell: SquareCrop?
    var adjustment: FrameAdjustment
    var tool: FrameEditorTool
    var zoomPercent: Int
    var showsGrid: Bool
    var showsCrosshair: Bool
    var showsWarning: Bool
    var accessibilityLabel: String = ""
    var accessibilityValue: String = ""
    var accessibilityHelp: String = ""
}

/// A precision crop canvas with eight square-locked resize handles, dimmed surroundings, rule-of-
/// thirds guides and a marked center crosshair. It draws the source pixels nearest-neighbor.
struct FrameEditorCanvas: NSViewRepresentable {
    let configuration: FrameCanvasConfiguration
    let onAdjustmentChange: (FrameAdjustment) -> Void

    func makeNSView(context: Context) -> FrameCanvasNSView {
        let view = FrameCanvasNSView(frame: .zero)
        view.onAdjustmentChange = onAdjustmentChange
        view.apply(configuration)
        return view
    }

    func updateNSView(_ view: FrameCanvasNSView, context: Context) {
        view.onAdjustmentChange = onAdjustmentChange
        view.apply(configuration)
    }
}

final class FrameCanvasNSView: NSView {
    var onAdjustmentChange: ((FrameAdjustment) -> Void)?

    var configuration: FrameCanvasConfiguration?
    var trackingAreaReference: NSTrackingArea?
    var drag: DragState?

    enum DragTarget {
        case handle(SpriteCropHandle)
        case moveCrop
        case alignContent
    }

    struct DragState {
        let target: DragTarget
        let startAdjustment: FrameAdjustment
        let startPoint: NSPoint
        let scale: CGFloat
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func apply(_ configuration: FrameCanvasConfiguration) {
        self.configuration = configuration
        updateAccessibility(configuration)
        needsDisplay = true
    }
}
