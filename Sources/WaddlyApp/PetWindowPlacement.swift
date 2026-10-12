import AppKit

/// Geometry for keeping the pet panel inside an available screen.
enum PetWindowPlacement {
    /// Clamps `origin` so a window of `size` stays inside the visible frame of the first screen it
    /// overlaps, falling back to the main screen and then to any screen. Used both when restoring a
    /// saved position and when the display configuration changes.
    static func clampedOrigin(
        _ origin: NSPoint,
        size: NSSize,
        visibleFrames: [NSRect],
        mainVisibleFrame: NSRect?
    ) -> NSPoint {
        let frame = NSRect(origin: origin, size: size)
        guard let visible = visibleFrames.first(where: { $0.intersects(frame) })
            ?? mainVisibleFrame
            ?? visibleFrames.first
        else { return origin }
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        return NSPoint(
            x: min(max(origin.x, visible.minX), maxX),
            y: min(max(origin.y, visible.minY), maxY)
        )
    }
}
