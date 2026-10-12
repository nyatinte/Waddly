import AppKit

/// Image view for pixel art: scaling must never smooth the sprite outlines.
///
/// `NSImageView` draws through the current graphics context, so the interpolation has to be set at
/// draw time; setting only the layer filters would have no effect.
@MainActor
class PixelImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        super.draw(dirtyRect)
    }

    /// Keeps the layer honest for any compositing that bypasses `draw(_:)`.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
    }
}

/// Honor the system "Reduce Motion" setting for the few animations the wizard adds.
enum MotionPreference {
    static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
