import AppKit
import SwiftUI

@MainActor
private final class DragDemonstrationModel: ObservableObject {
    @Published var source: CGPoint = .zero
    @Published var target: CGPoint = .zero
}

@MainActor
final class DragDemonstrationOverlayController {
    private let model = DragDemonstrationModel()
    private var panel: NSPanel?

    func update(screen: NSScreen, source: NSPoint, target: CGPoint) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            panel.contentView = NSHostingView(rootView: DragDemonstrationOverlayView(model: model))
            self.panel = panel
        }
        panel?.setFrame(screen.frame, display: true)
        model.source = CGPoint(x: source.x - screen.frame.minX, y: screen.frame.maxY - source.y)
        model.target = CGPoint(x: target.x - screen.frame.minX, y: screen.frame.maxY - target.y)
        panel?.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

@MainActor
private struct DragDemonstrationOverlayView: View {
    @ObservedObject var model: DragDemonstrationModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    private let duration = 4.0

    var body: some View {
        GeometryReader { geometry in
            if !reduceMotion {
                TimelineView<AnimationTimelineSchedule, AnyView>(
                    .animation(minimumInterval: 1.0 / 30.0, paused: false)
                ) { context in
                    frame(
                        at: context.date.timeIntervalSinceReferenceDate,
                        size: geometry.size
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private func frame(at referenceTime: TimeInterval, size: CGSize) -> AnyView {
        let start = model.source
        let end = model.target
        let time = referenceTime.truncatingRemainder(dividingBy: duration)
        let grabOffset = CGPoint(x: -18, y: -16)
        let grabPoint = CGPoint(x: start.x + grabOffset.x, y: start.y + grabOffset.y)
        let dragProgress = Self.smooth((time - 0.4) / 1.42)
        let pathPoint = Self.cubic(
            from: start,
            control1: CGPoint(x: start.x + (end.x - start.x) * 0.32, y: start.y - 24),
            control2: CGPoint(x: end.x - (end.x - start.x) * 0.28, y: end.y - 12),
            to: end,
            progress: dragProgress
        )
        let cursorHotspot = CGPoint(x: pathPoint.x + grabOffset.x, y: pathPoint.y + grabOffset.y)
        let pointerCenter = CGPoint(x: cursorHotspot.x + 11, y: cursorHotspot.y + 11)
        let pressProgress = Self.smooth((time - 0.2) / 0.13)
        let dropProgress = Self.smooth((time - 1.8) / 0.16)
        let targetGhostScale = DesignTokens.Control.dragGhostSize / DesignTokens.Control.dragIconSize
        let ghostScale = 1 - (1 - targetGhostScale) * CGFloat(dragProgress)
        return AnyView(ZStack {
            pressCue(time: time, progress: pressProgress, point: grabPoint)
            if time >= 0.4, time < 1.98 {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: DesignTokens.Control.dragIconSize, height: DesignTokens.Control.dragIconSize)
                    .scaleEffect(ghostScale)
                    .shadow(color: .black.opacity(0.2), radius: 7, y: 3)
                    .opacity(time < 1.8 ? 1 : 1 - dropProgress)
                    .position(pathPoint)
            }
            if time >= 1.8, time < 2.2 {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .scaleEffect(0.85 + 0.15 * dropProgress)
                    .position(end)
            }
            if time < 2.2 {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .position(pointerCenter)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true))
    }

    @ViewBuilder
    private func pressCue(time: Double, progress: Double, point: CGPoint) -> some View {
        if time >= 0.2, time < 0.56 {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .overlay(Circle().stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5))
                .frame(width: 22, height: 22)
                .scaleEffect(1 - 0.18 * progress)
                .position(point)
        }
    }

    private static func smooth(_ progress: Double) -> Double {
        let value = min(max(progress, 0), 1)
        return value * value * (3 - 2 * value)
    }

    private static func cubic(
        from start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        to end: CGPoint,
        progress: Double
    ) -> CGPoint {
        let inverse = 1 - progress
        let startWeight = inverse * inverse * inverse
        let firstWeight = 3 * inverse * inverse * progress
        let secondWeight = 3 * inverse * progress * progress
        let endWeight = progress * progress * progress
        return CGPoint(
            x: startWeight * start.x + firstWeight * control1.x + secondWeight * control2.x + endWeight * end.x,
            y: startWeight * start.y + firstWeight * control1.y + secondWeight * control2.y + endWeight * end.y
        )
    }
}
