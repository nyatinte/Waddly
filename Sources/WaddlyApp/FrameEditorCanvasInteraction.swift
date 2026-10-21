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
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let configuration, configuration.source != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let layout = layout(for: configuration)
        let target: DragTarget? = if let handle = handle(at: point, layout: layout) {
            .handle(handle)
        } else if cropViewRect(layout: layout).contains(point) {
            configuration.tool == .crop ? .moveCrop : .alignContent
        } else {
            nil
        }
        guard let target else {
            drag = nil
            return
        }
        drag = DragState(
            target: target,
            startAdjustment: configuration.adjustment,
            startPoint: point,
            scale: layout.scale
        )
        if case .moveCrop = target {
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let configuration else { return }
        let point = convert(event.locationInWindow, from: nil)
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
        }
        self.drag = drag
        onAdjustmentChange?(adjustment)
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
        updateCursor(at: convert(event.locationInWindow, from: nil))
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
