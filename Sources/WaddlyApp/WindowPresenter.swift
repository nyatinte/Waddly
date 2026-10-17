import AppKit

/// Every way the app puts a window in front of the user.
///
/// Windows are the app's only visible output, and the test host is an ordinary AppKit process, so
/// a test that opens the pet or the setup wizard paints it over whatever the user is doing. This is
/// the seam for that: the app runs with `live`, and tests substitute a presenter whose windows are
/// fully transparent. A transparent window still shows, still becomes key, and still hosts sheets,
/// so the app's own state machine keeps running for real while nothing is drawn.
@MainActor
struct WindowPresenter {
    /// Brings the app forward, for windows the user is expected to type into.
    var activate: () -> Void
    /// Brings a window forward without taking focus: the pet must never steal a click.
    var reveal: (NSWindow) -> Void
    /// Reveals a window and hands it the keyboard.
    var focus: (NSWindow) -> Void
    /// Takes a window off screen.
    var hide: (NSWindow) -> Void
    /// Arrives a window by fading it in, so the pet's first appearance reads as an arrival.
    var revealFadingIn: (NSWindow, TimeInterval) -> Void
    /// Shows a modal alert as a sheet on `parent` and reports how it was dismissed.
    var presentAlert: (NSAlert, NSWindow, @escaping (NSApplication.ModalResponse) -> Void) -> Void

    static let live = WindowPresenter(
        activate: { NSApp.activate(ignoringOtherApps: true) },
        reveal: { $0.orderFrontRegardless() },
        focus: { $0.makeKeyAndOrderFront(nil) },
        hide: { $0.orderOut(nil) },
        revealFadingIn: { window, duration in
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            } completionHandler: {
                // An interrupted animation must never leave the window invisible.
                Task { @MainActor in window.alphaValue = 1 }
            }
        },
        presentAlert: { alert, parent, then in
            alert.beginSheetModal(for: parent, completionHandler: then)
        }
    )
}
