import AppKit
import Testing
@testable import WaddlyApp

/// The pet panel must stay on a screen that still exists after the display configuration changes.
struct PetWindowPlacementTests {
    private let size = NSSize(width: 240, height: 240)
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func keepsAnOriginThatIsAlreadyVisible() {
        let origin = NSPoint(x: 100, y: 200)
        let clamped = PetWindowPlacement.clampedOrigin(
            origin,
            size: size,
            visibleFrames: [screen],
            mainVisibleFrame: screen
        )
        #expect(clamped == origin)
    }

    @Test func pullsAnOriginBackInsideTheScreenItOverlaps() {
        let origin = NSPoint(x: 1300, y: -50)
        let clamped = PetWindowPlacement.clampedOrigin(
            origin,
            size: size,
            visibleFrames: [screen],
            mainVisibleFrame: screen
        )
        #expect(clamped == NSPoint(x: 1200, y: 0))
    }

    /// A removed display leaves the saved origin outside every remaining screen, so the pet falls
    /// back to the main screen instead of staying stranded.
    @Test func fallsBackToTheMainScreenWhenTheOriginIsOffEveryDisplay() {
        let origin = NSPoint(x: 2500, y: 100)
        let clamped = PetWindowPlacement.clampedOrigin(
            origin,
            size: size,
            visibleFrames: [screen],
            mainVisibleFrame: screen
        )
        #expect(clamped == NSPoint(x: 1200, y: 100))
    }

    @Test func keepsTheOriginWhenNoScreenIsAvailable() {
        let origin = NSPoint(x: 2500, y: 100)
        let clamped = PetWindowPlacement.clampedOrigin(
            origin,
            size: size,
            visibleFrames: [],
            mainVisibleFrame: nil
        )
        #expect(clamped == origin)
    }
}
