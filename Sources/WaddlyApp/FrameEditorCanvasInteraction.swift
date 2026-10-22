import AppKit
import SwiftUI
import WaddlyCore

extension FrameCanvasNSView {
    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    private func updateCursor(at point: NSPoint) {
        guard let configuration, configuration.source != nil else {
            NSCursor.arrow.set()
            return
        }
        let layout = layout(for: configuration)
        if let handle = handle(at: point, layout: layout) {
            switch handle {
            case .top, .bottom: NSCursor.resizeUpDown.set()
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .topLeft, .topRight, .bottomLeft, .bottomRight: NSCursor.crosshair.set()
            }
        } else if cropViewRect(layout: layout).contains(point) {
            (configuration.tool == .crop ? NSCursor.openHand : NSCursor.crosshair).set()
        } else if let drag, case .pan = drag.target {
            NSCursor.closedHand.set()
        } else {
            NSCursor.openHand.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let configuration, configuration.source != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let layout = layout(for: configuration)
        let cropRect = cropViewRect(layout: layout)
        if event.clickCount == 2, !cropRect.contains(point) {
            // Double-click empty space resets the viewport.
            panOffset = .zero
            onZoomChange?(1)
            needsDisplay = true
            drag = nil
            return
        }
        let target: DragTarget = if let handle = handle(at: point, layout: layout) {
            .handle(handle)
        } else if cropRect.contains(point) {
            configuration.tool == .crop ? .moveCrop : .alignContent
        } else {
            .pan
        }
        drag = DragState(
            target: target,
            startAdjustment: configuration.adjustment,
            startPoint: point,
            scale: layout.scale,
            startPanOffset: panOffset
        )
        if case .moveCrop = target {
            NSCursor.closedHand.set()
        } else if case .pan = target {
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let configuration else { return }
        let point = convert(event.locationInWindow, from: nil)
        if case .pan = drag.target {
            panOffset = CGPoint(
                x: drag.startPanOffset.x + point.x - drag.startPoint.x,
                y: drag.startPanOffset.y + point.y - drag.startPoint.y
            )
            needsDisplay = true
            return
        }
        let deltaX = Int(((point.x - drag.startPoint.x) / drag.scale).rounded())
        let deltaY = Int(((point.y - drag.startPoint.y) / drag.scale).rounded())
        let geometry = FrameEditGeometry(
            sourceSide: configuration.sourceSide,
            cellOriginX: configuration.nominalCell?.x,
            cellOriginY: configuration.nominalCell?.y,
            cellSize: configuration.nominalCell?.size
        )

        var adjustment = drag.startAdjustment
        switch drag.target {
        case let .handle(handle):
            adjustment.crop = geometry.resized(
                drag.startAdjustment.crop,
                handle: handle,
                deltaX: deltaX,
                deltaY: deltaY
            )
            adjustment.offsetX = drag.startAdjustment.offsetX
            adjustment.offsetY = drag.startAdjustment.offsetY
        case .moveCrop:
            adjustment.crop = geometry.moved(
                drag.startAdjustment.crop,
                deltaX: deltaX,
                deltaY: deltaY
            )
        case .alignContent:
            let offset = geometry.clampedOffset(
                x: drag.startAdjustment.offsetX + deltaX,
                y: drag.startAdjustment.offsetY + deltaY,
                crop: drag.startAdjustment.crop
            )
            adjustment.offsetX = offset.x
            adjustment.offsetY = offset.y
        case .pan:
            return
        }
        self.drag = drag
        onAdjustmentChange?(adjustment)
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    // MARK: - Pan and zoom gestures

    /// Trackpad / wheel scrolling pans the viewport; Option-scroll zooms.
    override func scrollWheel(with event: NSEvent) {
        guard configuration?.source != nil else { return }
        if event.modifierFlags.contains(.option) {
            let factor = 1 + event.scrollingDeltaY * 0.01
            onZoomChange?((configuration?.zoomScale ?? 1) * factor)
            return
        }
        panOffset.x += event.scrollingDeltaX
        panOffset.y += event.scrollingDeltaY
        needsDisplay = true
    }

    /// Trackpad pinch zoom. The viewport keeps its pan; the context scales around its center.
    override func magnify(with event: NSEvent) {
        guard configuration?.source != nil else { return }
        let factor = max(0.1, 1 + event.magnification)
        onZoomChange?((configuration?.zoomScale ?? 1) * factor)
    }

    /// Double-tap on the trackpad or a reset from tests returns to the fitted view.
    func resetViewport() {
        panOffset = .zero
        onZoomChange?(1)
        needsDisplay = true
    }

    // MARK: - Accessibility

    func updateAccessibility(_ configuration: FrameCanvasConfiguration) {
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(configuration.accessibilityLabel)
        setAccessibilityValue(configuration.accessibilityValue)
        setAccessibilityHelp(configuration.accessibilityHelp)
    }
}
