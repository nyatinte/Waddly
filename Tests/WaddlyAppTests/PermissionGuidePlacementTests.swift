import AppKit
import Testing
@testable import WaddlyApp

/// The guide window must stay clear of the System Settings window and of Waddly's own windows.
struct PermissionGuidePlacementTests {
    private let visible = NSRect(x: 0, y: 0, width: 1710, height: 1010)
    private let panel = NSSize(width: 300, height: 236)

    @Test func sitsBelowTheSettingsWindowWhenThereIsRoom() {
        let settings = CGRect(x: 500, y: 400, width: 700, height: 500)
        let origin = PermissionGuidePlacement.origin(
            windowSize: panel,
            settings: settings,
            visible: visible,
            ownWindows: []
        )
        #expect(origin == NSPoint(x: 730, y: 154))
        #expect(!PermissionGuidePlacement.overlaps(origin, size: panel, [settings]))
    }

    @Test func movesToTheSideWhenTheSettingsWindowReachesTheBottom() {
        let settings = CGRect(x: 500, y: 40, width: 700, height: 500)
        let origin = PermissionGuidePlacement.origin(
            windowSize: panel,
            settings: settings,
            visible: visible,
            ownWindows: []
        )
        #expect(!PermissionGuidePlacement.overlaps(origin, size: panel, [settings]))
        #expect(PermissionGuidePlacement.fits(origin, size: panel, into: visible))
        #expect(origin.x < settings.minX)
    }

    @Test func prefersTheRightSideWhenOurOwnWindowOccupiesTheLeft() {
        let settings = CGRect(x: 500, y: 40, width: 700, height: 500)
        let ownWindow = CGRect(x: 0, y: 0, width: 500, height: 800)
        let origin = PermissionGuidePlacement.origin(
            windowSize: panel,
            settings: settings,
            visible: visible,
            ownWindows: [ownWindow]
        )
        #expect(origin.x > settings.maxX)
        #expect(!PermissionGuidePlacement.overlaps(origin, size: panel, [ownWindow, settings]))
    }

    @Test func ignoresOverlaysSmallerThanADialog() {
        let settings = CGRect(x: 500, y: 40, width: 700, height: 500)
        // The desktop pet is 180pt square and must not push the helper to the other side.
        let pet = CGRect(x: 120, y: 200, width: 180, height: 180)
        let origin = PermissionGuidePlacement.origin(
            windowSize: panel,
            settings: settings,
            visible: visible,
            ownWindows: [pet]
        )
        #expect(origin.x < settings.minX)
    }

    @Test func alwaysStaysInsideTheVisibleFrame() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1710, height: 1010),
            CGRect(x: 10, y: 20, width: 600, height: 900),
            CGRect(x: 1600, y: 900, width: 500, height: 300),
            CGRect(x: 300, y: 300, width: 1200, height: 700)
        ]
        for settings in frames {
            let origin = PermissionGuidePlacement.origin(
                windowSize: panel,
                settings: settings,
                visible: visible,
                ownWindows: []
            )
            #expect(
                PermissionGuidePlacement.fits(origin, size: panel, into: visible),
                "escaped the visible frame for \(settings)"
            )
        }
    }

    /// Quartz measures downwards from the primary display's top edge, AppKit upwards from its
    /// bottom edge. A settings window in the top half has to end up in the top half.
    @Test func convertsQuartzBoundsIntoAppKitCoordinates() {
        let primary = CGRect(x: 0, y: 0, width: 1710, height: 1010)
        let topOfTheDisplay = CGRect(x: 200, y: 0, width: 800, height: 500)
        let converted = PermissionGuidePlacement.appKitRect(
            quartz: topOfTheDisplay,
            primaryFrame: primary
        )
        #expect(converted == CGRect(x: 200, y: 510, width: 800, height: 500))
        #expect(converted.maxY == primary.maxY)
    }

    /// A display placed above the primary one has negative AppKit coordinates, and the conversion
    /// must not fold it onto the primary display.
    @Test func keepsNegativeCoordinatesForADisplayAboveThePrimary() {
        let primary = CGRect(x: 0, y: 0, width: 1710, height: 1010)
        let above = CGRect(x: 40, y: -900, width: 1512, height: 900)
        let converted = PermissionGuidePlacement.appKitRect(quartz: above, primaryFrame: primary)
        #expect(converted == CGRect(x: 40, y: 1010, width: 1512, height: 900))
    }

    /// When nothing fits cleanly, the guide covers the settings sidebar rather than the app list:
    /// the list is the drop target the guide is asking the user to drag onto.
    @Test func coversTheSidebarInsteadOfTheAppListWhenNothingFits() {
        let settings = CGRect(x: 200, y: 200, width: 1300, height: 600)
        let origin = PermissionGuidePlacement.origin(
            windowSize: panel,
            settings: settings,
            visible: visible,
            ownWindows: []
        )
        #expect(origin == NSPoint(x: 12, y: 516))
        #expect(PermissionGuidePlacement.fits(origin, size: panel, into: visible))
        let list = PermissionGuidePlacement.listArea(in: settings)
        #expect(!NSRect(origin: origin, size: panel).intersects(list))
    }

    /// The compact guide is narrow enough to park beside a settings window that fills the screen, so
    /// the only System Settings column it can cover is the sidebar.
    @Test func compactGuideKeepsTheAppListVisibleOnASmallDisplay() {
        let visible = NSRect(x: 0, y: 0, width: 1205, height: 602)
        let settings = CGRect(x: 290, y: 0, width: 915, height: 602)
        let compact = SetupMetrics.compactGuideSize
        let origin = PermissionGuidePlacement.origin(
            windowSize: compact,
            settings: settings,
            visible: visible,
            ownWindows: []
        )
        let list = PermissionGuidePlacement.listArea(in: settings)
        #expect(!NSRect(origin: origin, size: compact).intersects(list))
        #expect(PermissionGuidePlacement.fits(origin, size: compact, into: visible))
    }

    @Test func guideFollowingStopsOnAUserMoveAndResumesOnBegin() {
        var following = GuideFollowing()
        following.begin()
        following.recordProgrammaticMove(to: NSPoint(x: 10, y: 20))
        following.recordMove(to: NSPoint(x: 10, y: 20))
        #expect(following.isActive)
        following.recordMove(to: NSPoint(x: 40, y: 60))
        #expect(!following.isActive)
        following.begin()
        #expect(following.isActive)
    }

    /// Before the app has parked the window once, any move is the user's, so a drag during the
    /// first polling interval stops the guide instead of being overridden by the next tick.
    @Test func guideFollowingTreatsAMoveBeforeTheFirstParkAsTheUsers() {
        var following = GuideFollowing()
        following.begin()
        following.recordMove(to: NSPoint(x: 40, y: 60))
        #expect(!following.isActive)
    }
}
