import AppKit

@main
struct WaddlyAppMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
