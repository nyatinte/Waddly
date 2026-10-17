import AppKit
@testable import WaddlyApp

extension WindowPresenter {
    /// The presenter every test runs with: the same AppKit behaviour as `live`, with windows that
    /// are fully transparent.
    ///
    /// Tests run in a real AppKit process, so a suite that opens the pet, the setup wizard, or a
    /// settings window would paint them over whatever the user is doing while `mise run test` runs.
    /// A transparent window still shows, still becomes key, and still hosts sheets, so the app's own
    /// state machine is exercised for real; the compositor simply draws nothing.
    static let invisible: WindowPresenter = {
        var presenter = WindowPresenter.live
        presenter.reveal = { window in
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        presenter.focus = { window in
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
        }
        presenter.revealFadingIn = { window, _ in
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        presenter.presentAlert = { alert, parent, then in
            // Attaching a sheet orders its parent front too, so both have to stay transparent.
            parent.alphaValue = 0
            alert.window.alphaValue = 0
            WindowPresenter.live.presentAlert(alert, parent, then)
        }
        return presenter
    }()
}

/// Builds an app whose windows never reach the desktop. Every suite that touches windows uses this
/// instead of `AppDelegate(...)` directly, so a test run cannot flash the app over the user's work.
@MainActor
func makeTestApp(settings: AppSettings = .standard) -> AppDelegate {
    AppDelegate(settings: settings, presenter: .invisible)
}
