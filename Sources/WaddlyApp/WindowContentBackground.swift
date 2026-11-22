import AppKit
import SwiftUI

/// A system window material, distinct from Liquid Glass controls. AppKit adapts it to the
/// appearance, focus and accessibility settings and blends with content behind the window.
@MainActor
func makeWindowContentMaterial() -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .underWindowBackground
    view.blendingMode = .behindWindow
    view.state = .followsWindowActiveState
    return view
}

private struct WindowContentMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        makeWindowContentMaterial()
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    @ViewBuilder
    func windowContentBackground() -> some View {
        if #available(macOS 26.0, *) {
            background(WindowContentMaterial())
        } else {
            background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
