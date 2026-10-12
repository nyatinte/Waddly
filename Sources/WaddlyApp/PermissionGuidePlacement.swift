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
        if let fitsAndClear {
            return fitsAndClear
        }

        // Nothing fit cleanly. Clamp first, then prefer the placement that hides the least of System
        // Settings so its app list stays reachable, while still avoiding Waddly's own windows.
        let clampedCandidates = candidates.map { clamped($0, size: windowSize, into: visible) }
        let clearOfOwn = clampedCandidates.filter { !overlaps($0, size: windowSize, relevantOwn) }
        let pool = clearOfOwn.isEmpty ? clampedCandidates : clearOfOwn
        let leastCovering = pool.min { first, second in
            let firstCoverage = overlapArea(first, size: windowSize, with: settings)
            let secondCoverage = overlapArea(second, size: windowSize, with: settings)
            return firstCoverage < secondCoverage
        }
        return leastCovering ?? clamped(below, size: windowSize, into: visible)
    }

    static func overlapArea(_ origin: NSPoint, size: NSSize, with rect: CGRect) -> CGFloat {
        let intersection = NSRect(origin: origin, size: size).intersection(rect)
        return intersection.isNull ? 0 : intersection.width * intersection.height
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
        guard !pids.isEmpty, let primaryFrame = NSScreen.screens.first?.frame else { return nil }
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
            return appKitRect(quartz: rect, primaryFrame: primaryFrame)
        }.max { $0.width * $0.height < $1.width * $1.height }
    }

    /// `kCGWindowBounds` measures from the top-left corner of the primary display, while `NSScreen`
    /// and `NSWindow` measure from its bottom-left. Everything downstream compares this rectangle
    /// with screen frames and passes the result to `setFrameOrigin`, so convert it once, here.
    ///
    /// The primary display's frame is what does the flipping, not the active display's: a display
    /// above the primary one has negative coordinates, which the conversion has to preserve.
    static func appKitRect(quartz rect: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Tracks whether the guide still follows System Settings. A user move stops the following so the
/// window can be repositioned freely; programmatic moves are recorded so they are not mistaken for
/// user moves.
struct GuideFollowing {
    private(set) var isActive = true
    private var lastProgrammaticOrigin: NSPoint?

    mutating func begin() {
        isActive = true
        lastProgrammaticOrigin = nil
    }

    mutating func recordProgrammaticMove(to origin: NSPoint) {
        lastProgrammaticOrigin = origin
    }

    /// A move that does not match the last programmatic origin is the user's. Before the app has
    /// moved the window once, any move is the user's.
    mutating func recordMove(to origin: NSPoint) {
        guard isActive else { return }
        if let last = lastProgrammaticOrigin {
            let matchesRecorded = abs(last.x - origin.x) <= 1 && abs(last.y - origin.y) <= 1
            if matchesRecorded {
                return
            }
        }
        isActive = false
    }
}
