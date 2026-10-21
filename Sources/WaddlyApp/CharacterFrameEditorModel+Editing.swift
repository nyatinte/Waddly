import AppKit
import WaddlyCore

/// Crop and alignment mutations for the selected frame. Every setter clamps through the frame's
/// geometry so numeric fields, the canvas, and the D-pad can never disagree or leave valid bounds.
extension CharacterFrameEditorModel {
    // MARK: - Editing

    func setCropSize(_ size: Int) {
        guard let geometry else { return }
        updateCurrent { adjustment in
            let clampedSize = min(max(size, geometry.minimumSide), geometry.sourceSide)
            adjustment.crop = SquareCrop(
                x: adjustment.crop.x + (adjustment.crop.size - clampedSize) / 2,
                y: adjustment.crop.y + (adjustment.crop.size - clampedSize) / 2,
                size: clampedSize
            )
        }
    }

    func setCropOriginX(_ originX: Int) {
        updateCurrent { adjustment in
            adjustment.crop.x = originX
        }
    }

    func setCropOriginY(_ originY: Int) {
        updateCurrent { adjustment in
            adjustment.crop.y = originY
        }
    }

    func setOffsetX(_ offsetX: Int) {
        updateCurrent { adjustment in
            adjustment.offsetX = offsetX
        }
    }

    func setOffsetY(_ offsetY: Int) {
        updateCurrent { adjustment in
            adjustment.offsetY = offsetY
        }
    }

    func nudge(deltaX: Int, deltaY: Int) {
        updateCurrent { adjustment in
            adjustment.offsetX += deltaX
            adjustment.offsetY += deltaY
        }
    }

    func resetPosition() {
        updateCurrent { adjustment in
            adjustment.offsetX = 0
            adjustment.offsetY = 0
        }
    }

    func isFrameEdited(_ slot: SpriteFrameSlot) -> Bool {
        editing?.isEdited(slot) ?? false
    }

    func resetCurrentFrame() {
        guard var editing else { return }
        editing.reset(selectedSlot)
        self.editing = editing
        adjustedThumbnails[selectedSlot] = nil
    }

    func resetAll() {
        guard var editing else { return }
        editing.resetAll()
        self.editing = editing
        adjustedThumbnails.removeAll()
    }

    /// Applies one canvas gesture result. The canvas already works in integer source pixels.
    func applyCanvasAdjustment(_ adjustment: FrameAdjustment) {
        updateCurrent { current in
            current = adjustment
        }
    }

    private func updateCurrent(_ transform: (inout FrameAdjustment) -> Void) {
        guard var editing, let geometry else { return }
        var adjustment = editing.adjustment(for: selectedSlot)
        transform(&adjustment)
        adjustment = adjustment.normalized(geometry: geometry)
        editing.setAdjustment(adjustment, for: selectedSlot)
        self.editing = editing
        refreshAdjustedThumbnail(for: selectedSlot)
    }
}
