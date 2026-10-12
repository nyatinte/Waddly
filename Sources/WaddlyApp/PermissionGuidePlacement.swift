import AppKit

/// Geometry for parking the setup window beside System Settings while the user drags the app in.
///
/// Reading another app's window frame needs no accessibility or screen-recording permission:
/// only `kCGWindowName` is gated, and this filters by owner PID instead.
enum PermissionGuidePlacement {
    static let sidebarWidth: CGFloat = 230
    static let gap: CGFloat = 10
    static let screenInset: CGFloat = 12
    /// Tiny overlays such as the desktop pet must not push the window around.
    static let ownWindowMinimumSide: CGFloat = 240

    /// Places the guide window below the settings window when there is room (which structurally
    /// cannot cover the app list), then to a side. `ownWindows` keeps it off our own windows.
    static func origin(
        windowSize: NSSize,
        settings: CGRect,
        visible: NSRect,
        ownWindows: [CGRect]
    ) -> NSPoint {
        let below = NSPoint(x: settings.minX + sidebarWidth, y: settings.minY - windowSize.height - gap)
        let left = NSPoint(x: settings.minX - windowSize.width - gap, y: settings.maxY - windowSize.height - 48)
        let right = NSPoint(x: settings.maxX + gap, y: settings.maxY - windowSize.height - 48)
        let candidates = [below, left, right]
        let relevantOwn = ownWindows.filter {
            $0.width >= ownWindowMinimumSide && $0.height >= ownWindowMinimumSide
        }
        // Test the raw candidates: clamping first would make every candidate "fit" and always pick `below`.
        let fitsAndClear = candidates.first {
            fits($0, size: windowSize, into: visible) && !overlaps($0, size: windowSize, relevantOwn)
        }
        let chosen = fitsAndClear
            ?? candidates.first { !overlaps($0, size: windowSize, relevantOwn) }
            ?? below
        return clamped(chosen, size: windowSize, into: visible)
    }

    static func fits(_ origin: NSPoint, size: NSSize, into visible: NSRect) -> Bool {
        visible.contains(NSRect(origin: origin, size: size))
    }

    static func overlaps(_ origin: NSPoint, size: NSSize, _ windows: [CGRect]) -> Bool {
        let rect = NSRect(origin: origin, size: size)
        return windows.contains { $0.intersects(rect) }
    }

    static func clamped(_ origin: NSPoint, size: NSSize, into visible: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visible.minX + screenInset), visible.maxX - size.width - screenInset),
            y: min(max(origin.y, visible.minY + screenInset), visible.maxY - size.height - screenInset)
        )
    }

    static func systemSettingsWindowFrame() -> CGRect? {
        let identifiers = ["com.apple.systempreferences", "com.apple.SystemSettings"]
        let pids = identifiers.flatMap { identifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).map(\.processIdentifier)
        }
        guard !pids.isEmpty else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        return windows.compactMap { window -> CGRect? in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 320, rect.height > 240
            else { return nil }
            return rect
        }.max { $0.width * $0.height < $1.width * $1.height }
    }

    static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
