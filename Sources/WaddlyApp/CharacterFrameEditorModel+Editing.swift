import AppKit
import WaddlyCore

/// Crop and alignment mutations for the selected frame. Every setter clamps through the frame's
/// geometry so numeric fields, the canvas, and the D-pad can never disagree or leave valid bounds.
extension CharacterFrameEditorModel {
    // MARK: - Editing

    func setCropSize(_ size: Int) {
        guard let geometry else { return }
        let range = cropSizeRange
        let clampedSize = min(max(size, geometry.minimumSide), range.upperBound)
        let crop = currentAdjustment.crop
        let anchor = cropSizeAnchor.flatMap { $0.slot == selectedSlot ? $0 : nil }
            ?? CropSizeAnchor(
                slot: selectedSlot,
                centerX: Double(crop.x) + Double(crop.size) / 2,
                centerY: Double(crop.y) + Double(crop.size) / 2
            )
        cropSizeAnchor = anchor
        updateCurrent { adjustment in
            adjustment.crop = SquareCrop(
                x: Int((anchor.centerX - Double(clampedSize) / 2).rounded()),
                y: Int((anchor.centerY - Double(clampedSize) / 2).rounded()),
                size: clampedSize
            )
        }
    }

    func setCropOriginX(_ originX: Int) {
        cropSizeAnchor = nil
        updateCurrent { adjustment in
            adjustment.crop.x = originX
        }
    }

    func setCropOriginY(_ originY: Int) {
        cropSizeAnchor = nil
        updateCurrent { adjustment in
            adjustment.crop.y = originY
        }
    }

    func setOffsetX(_ offsetX: Int) {
        cropSizeAnchor = nil
        updateCurrent { adjustment in
            adjustment.offsetX = offsetX
        }
    }

    func setOffsetY(_ offsetY: Int) {
        cropSizeAnchor = nil
        updateCurrent { adjustment in
            adjustment.offsetY = offsetY
        }
    }

    func nudge(deltaX: Int, deltaY: Int) {
        cropSizeAnchor = nil
        updateCurrent { adjustment in
            adjustment.offsetX += deltaX
            adjustment.offsetY += deltaY
        }
    }

    func resetPosition() {
        cropSizeAnchor = nil
        updateCurrent { adjustment in
            adjustment.offsetX = 0
            adjustment.offsetY = 0
        }
    }

    func isFrameEdited(_ slot: SpriteFrameSlot) -> Bool {
        editing?.isEdited(slot) ?? false
    }

    func resetCurrentFrame() {
        cropSizeAnchor = nil
        guard var editing else { return }
        editing.reset(selectedSlot)
        self.editing = editing
        adjustedThumbnails[selectedSlot] = nil
    }

    func resetAll() {
        cropSizeAnchor = nil
        guard var editing else { return }
        editing.resetAll()
        self.editing = editing
        adjustedThumbnails.removeAll()
    }

    /// Applies one canvas gesture result. The canvas already works in integer source pixels.
    func applyCanvasAdjustment(_ adjustment: FrameAdjustment) {
        cropSizeAnchor = nil
        updateCurrent { current in
            current = adjustment
        }
    }

    private func updateCurrent(_ transform: (inout FrameAdjustment) -> Void) {
        guard var editing, let geometry else { return }
        var adjustment = editing.adjustment(for: selectedSlot)
        transform(&adjustment)
        adjustment.crop.size = min(adjustment.crop.size, canvasSide(for: selectedSlot))
        adjustment = adjustment.normalized(geometry: geometry)
        editing.setAdjustment(adjustment, for: selectedSlot)
        self.editing = editing
        refreshAdjustedThumbnail(for: selectedSlot)
    }
}
