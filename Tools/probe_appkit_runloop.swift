import AppKit

/// Independent #131 reproducer; no Waddly/Testing imports, preferences, images or input monitoring.
/// The default dispatches target/action. `--perform-click` exercises AppKit's event-tracking loop.
/// On affected runtimes the latter can exit 0 without printing PROBE_COMPLETED: check the marker.
@MainActor
private final class ProbeTarget: NSObject {
    var count = 0

    @objc func invoke(_ sender: NSButton) {
        count += 1
    }
}

@main
private struct AppKitRunLoopProbe {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let performClick = CommandLine.arguments.contains("--perform-click")
        let target = ProbeTarget()
        report("PROBE_STARTED mode=\(performClick ? "performClick" : "targetAction")")
        for index in 0 ..< 10 {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            let button = NSButton(title: "Probe", target: target, action: #selector(ProbeTarget.invoke(_:)))
            window.contentView = button
            window.orderFrontRegardless()
            if performClick {
                button.performClick(nil)
            } else {
                precondition(button.sendAction(button.action, to: button.target))
            }
            try await Task.sleep(for: .milliseconds(100))
            window.close()
            report("PROBE_CYCLE \(index)")
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(target.count == 10)
        report("PROBE_COMPLETED actions=\(target.count)")
    }

    private static func report(_ message: String) {
        FileHandle.standardOutput.write(Data("\(message)\n".utf8))
    }
}
