import AppKit
import WaddlyCore

/// Navigation, accessibility labels, source lookup, and thumbnail caches for the frame editor.
extension CharacterFrameEditorModel {
    func selectPreviousFrame() {
        let all = SpriteFrameSlot.allCases
        guard let index = all.firstIndex(of: selectedSlot), index > 0 else { return }
        selectedSlot = all[index - 1]
    }

    func selectNextFrame() {
        let all = SpriteFrameSlot.allCases
        guard let index = all.firstIndex(of: selectedSlot), index + 1 < all.count else { return }
        selectedSlot = all[index + 1]
    }

    var canSelectPreviousFrame: Bool {
        selectedSlot.rawValue > 0
    }

    var canSelectNextFrame: Bool {
        selectedSlot.rawValue + 1 < SpriteFrameSlot.allCases.count
    }

    func sourceImage(for slot: SpriteFrameSlot) -> CGImage? {
        if let sheet {
            return sheet
        }
        let images = sourceFrames[slot.category]
        guard images.indices.contains(slot.frameIndexInCategory) else { return nil }
        return images[slot.frameIndexInCategory].cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    var sourceName: String? {
        guard isSheetMode, let cellSize = editing?.cellSize, cellSize > 0 else { return nil }
        return importModel?.sourceName ?? localization.string(for: .frameEditorSavedSource)
    }

    var sourceDimensionsDescription: String? {
        guard isSheetMode, let cellSize = editing?.cellSize, cellSize > 0 else { return nil }
        return String(
            format: localization.string(for: .frameEditorSourceDimensionsFormat),
            cellSize * 3,
            cellSize
        )
    }

    var frameAccessibilityLabel: String {
        Self.accessibilityLabel(for: selectedSlot, edited: isCurrentFrameEdited, localization: localization)
    }

    static func accessibilityLabel(
        for slot: SpriteFrameSlot,
        edited: Bool,
        localization: LocalizationController
    ) -> String {
        let category = slot.category.title(using: localization)
        let count = SpriteFrameSlot.slots(for: slot.category).count
        let base = String(
            format: localization.string(for: .frameEditorFrameA11yFormat),
            category,
            slot.frameIndexInCategory + 1,
            count
        )
        return edited ? base + localization.string(for: .frameEditorEditedSuffix) : base
    }

    // MARK: - Thumbnails

    func renderBaseThumbnails() -> [SpriteFrameSlot: NSImage] {
        guard let editing else { return [:] }
        var result: [SpriteFrameSlot: NSImage] = [:]
        for slot in SpriteFrameSlot.allCases {
            guard let source = sourceImage(for: slot) else { continue }
            let baseline = FrameAdjustment.baseline(
                slot: slot,
                geometry: editing.geometry(for: slot)
            )
            result[slot] = SpriteFrameRenderer.renderCanvasNSImage(
                source: source,
                adjustment: baseline,
                canvasSide: canvasSide(for: slot),
                cappedOutputSide: Self.thumbnailSide
            )
        }
        return result
    }

    func refreshAdjustedThumbnail(for slot: SpriteFrameSlot) {
        guard let editing, editing.isEdited(slot), let source = sourceImage(for: slot),
              let image = SpriteFrameRenderer.renderCanvasNSImage(
                  source: source,
                  adjustment: editing.adjustment(for: slot),
                  canvasSide: canvasSide(for: slot),
                  cappedOutputSide: Self.thumbnailSide
              )
        else {
            adjustedThumbnails[slot] = nil
            return
        }
        adjustedThumbnails[slot] = image
    }
}
