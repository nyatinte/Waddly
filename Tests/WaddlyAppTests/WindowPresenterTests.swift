import AppKit
import Testing
@testable import WaddlyApp

/// The seam that keeps a test run off the user's screen. Its whole point is that it behaves like the
/// real presenter for everything except drawing, so these are the promises the rest of the suites
/// rely on: windows still open, sheets still attach and report, and only the pixels are missing.
@MainActor struct WindowPresenterTests {
    @Test func invisibleWindowsStillOpenAndClose() {
        let window = makeWindow()
        defer { window.close() }

        WindowPresenter.invisible.reveal(window)
        #expect(window.isVisible)
        #expect(window.alphaValue == 0)

        WindowPresenter.invisible.hide(window)
        #expect(!window.isVisible)

        WindowPresenter.invisible.focus(window)
        #expect(window.isVisible)
        #expect(window.alphaValue == 0)
    }

    /// Sheets are how the app asks the user to confirm an import, and the suites end them
    /// themselves, so an invisible alert still has to attach for real.
    @Test func invisibleAlertsStillAttachAsSheets() async {
        let parent = makeWindow()
        defer { parent.close() }
        let alert = NSAlert()
        alert.messageText = "confirm"
        alert.addButton(withTitle: "ok")
        alert.addButton(withTitle: "cancel")

        let response = await withCheckedContinuation { continuation in
            WindowPresenter.invisible.presentAlert(alert, parent) { response in
                continuation.resume(returning: response)
            }
            #expect(alert.window.isSheet)
            #expect(alert.window.sheetParent === parent)
            #expect(alert.window.alphaValue == 0)
            parent.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
        }
        #expect(response == .alertFirstButtonReturn)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}
