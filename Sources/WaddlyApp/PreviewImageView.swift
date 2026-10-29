import AppKit
import QuartzCore

/// A layer-hosting view updates only the sprite instead of redrawing the surrounding window.
@MainActor
final class PreviewImageView: NSView {
    var image: NSImage? {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            CATransaction.commit()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let spriteLayer = CALayer()
        spriteLayer.contentsGravity = .resizeAspect
        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .nearest
        layer = spriteLayer
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
