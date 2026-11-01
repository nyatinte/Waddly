import AppKit
import SwiftUI

@MainActor
final class PermissionGuidePanelController: NSWindowController, NSWindowDelegate {
    private weak var wizard: SetupWizardController?
    private let overlay = DragDemonstrationOverlayController()
    private var settingsTimer: Timer?
    private weak var sourceView: DraggableAppIconView?

    init(wizard: SetupWizardController) {
        self.wizard = wizard
        let size = SetupMetrics.permissionGuideSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = wizard.localizedString(.setupSetUpMonitoring)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.contentMinSize = SetupMetrics.permissionGuideMinimumSize
        panel.delegate = nil
        super.init(window: panel)
        panel.contentView = NSHostingView(rootView: PermissionGuidePanelView(
            wizard: wizard,
            onSourceView: { [weak self] in self?.sourceView = $0 },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onBack: { [weak self] in self?.returnToCharacterStep() },
            onLater: { [weak self] in self?.deferSetup() },
            onNext: { [weak self] in self?.continueSetup() },
            onRestart: { [weak wizard] in wizard?.relaunchApp() },
            onReadinessChanged: { [weak self] in self?.fitToContent() },
            onRealDragStarted: { [weak self] in self?.overlay.close() }
        ))
        panel.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let wizard, let panel = window as? NSPanel else { return }
        wizard.window?.orderOut(nil)
        panel.setContentSize(SetupMetrics.permissionGuideSize)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.orderFrontRegardless()
        fitToContent()
        placeBesideSettings()
        settingsTimer?.invalidate()
        settingsTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.placeBesideSettings() }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        if !wizard.permission.isGranted, !wizard.permission.isGuiding {
            wizard.permission.beginGuiding()
        } else if wizard.permission.readiness == .tapUnavailable {
            wizard.permission.retryTap()
        }
    }

    func refreshPlacement() {
        placeBesideSettings()
    }

    func stop() {
        settingsTimer?.invalidate()
        settingsTimer = nil
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        overlay.close()
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stop()
        wizard?.permission.stop()
        wizard?.window?.close()
    }

    @objc private func screenConfigurationChanged() {
        placeBesideSettings()
    }

    private func openSettings() {
        guard let wizard else { return }
        SystemSettingsLauncher.openInputMonitoringSettings()
        if !wizard.permission.isGuiding {
            wizard.permission.beginGuiding()
        }
        placeBesideSettings()
    }

    private func placeBesideSettings() {
        guard let panel = window else { return }
        guard let settings = PermissionGuidePlacement.systemSettingsWindowFrame() else {
            overlay.close()
            if let visible = NSScreen.main?.visibleFrame {
                let origin = NSPoint(
                    x: visible.midX - panel.frame.width / 2,
                    y: visible.midY - panel.frame.height / 2
                )
                panel.setFrameOrigin(PermissionGuidePlacement.clamped(origin, size: panel.frame.size, into: visible))
            }
            return
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let ownWindows = NSApp.windows
            .filter { $0 !== panel && $0.isVisible }
            .map(\.frame)
        let origin = PermissionGuidePlacement.origin(
            windowSize: panel.frame.size,
            settings: settings,
            visible: visible,
            ownWindows: ownWindows
        )
        panel.setFrameOrigin(origin)
        guard let wizard, !wizard.isMonitoringDragDemoStopped,
              wizard.monitoringReadiness == .permissionMissing,
              let sourceView, sourceView.window === panel, let screen
        else {
            overlay.close()
            return
        }
        let sourceRect = sourceView.convert(sourceView.bounds, to: nil)
        let source = panel.convertPoint(toScreen: NSPoint(x: sourceRect.midX, y: sourceRect.midY))
        let list = PermissionGuidePlacement.listArea(in: settings)
        let target = CGPoint(
            x: list.minX + list.width * 0.55,
            y: settings.minY + settings.height * 0.5
        )
        overlay.update(
            screen: screen,
            source: source,
            target: target
        )
    }

    private func fitToContent() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = window,
                  let hosting = panel.contentView as? NSHostingView<PermissionGuidePanelView>
            else { return }
            let width = SetupMetrics.permissionGuideSize.width
            let height = hosting.fittingSize.height
            guard height > 0 else { return }
            panel.setContentSize(NSSize(width: width, height: height))
            placeBesideSettings()
        }
    }

    private func returnToCharacterStep() {
        stop()
        guard let wizard else { return }
        wizard.permission.stop()
        wizard.permissionGuidePanelController = nil
        wizard.setStep(.pet)
        wizard.showWindow(nil)
    }

    private func deferSetup() {
        guard let wizard else { return }
        stop()
        wizard.permissionGuidePanelController = nil
        if wizard.isMonitoringSettings {
            wizard.permission.deferSetup()
            wizard.close()
        } else {
            wizard.deferMonitoring()
            wizard.showWindow(nil)
        }
    }

    private func continueSetup() {
        guard let wizard else { return }
        stop()
        wizard.permissionGuidePanelController = nil
        wizard.goNext()
        if !wizard.isMonitoringSettings {
            wizard.showWindow(nil)
        }
    }
}

@MainActor
private struct PermissionGuidePanelView: View {
    @ObservedObject var wizard: SetupWizardController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onSourceView: (DraggableAppIconView) -> Void
    let onOpenSettings: () -> Void
    let onBack: () -> Void
    let onLater: () -> Void
    let onNext: () -> Void
    let onRestart: () -> Void
    let onReadinessChanged: () -> Void
    let onRealDragStarted: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            if wizard.monitoringReadiness == .permissionMissing {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion || wizard.isMonitoringDragDemoStopped)) { context in
                    let sourceOpacity = Self.sourceOpacity(at: context.date.timeIntervalSinceReferenceDate)
                    AppIconDragSource(
                        localization: wizard.localization,
                        onViewCreated: onSourceView,
                        onDragStarted: {
                            wizard.isMonitoringDragDemoStopped = true
                            onRealDragStarted()
                        }
                    )
                    .frame(width: DesignTokens.Control.dragIconSize, height: DesignTokens.Control.dragIconSize)
                    .opacity(reduceMotion || wizard.isMonitoringDragDemoStopped ? 1 : sourceOpacity)
                    .accessibilityLabel(wizard.localizedString(.setupDragAppIcon))
                }
                .frame(height: DesignTokens.Control.dragIconSize)
            }

            Text(title)
                .font(DesignTokens.Typography.display)
                .multilineTextAlignment(.center)
            Text(instructions)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            switch wizard.monitoringReadiness {
            case .permissionMissing:
                Button(wizard.localizedString(.setupOpenSystemSettings), systemImage: "gearshape", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Text(wizard.localizedString(.setupGuideDragFallback))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .tapUnavailable:
                Button(wizard.localizedString(.setupRestartNow), action: onRestart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            case .awaitingReaction, .reactionObserved:
                EmptyView()
            }

            HStack {
                if !wizard.isMonitoringSettings {
                    Button(wizard.localizedString(.setupBack), action: onBack)
                        .buttonStyle(.bordered)
                }
                Spacer()
                if wizard.monitoringReadiness == .reactionObserved {
                    Button(wizard.localizedString(.setupNext), action: onNext)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(wizard.localizedString(.setupLater), action: onLater)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: SetupMetrics.permissionGuideSize.width)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: wizard.monitoringReadiness) { _, _ in onReadinessChanged() }
    }

    private var title: String {
        switch wizard.monitoringReadiness {
        case .permissionMissing: wizard.localizedString(.setupGuideTitle)
        case .tapUnavailable: wizard.localizedString(.setupRestartRequiredTitle)
        case .awaitingReaction: wizard.localizedString(.setupMonitoringWaitingTitle)
        case .reactionObserved: wizard.localizedString(.setupMonitoringGrantedTitle)
        }
    }

    private var instructions: String {
        switch wizard.monitoringReadiness {
        case .permissionMissing: wizard.localizedString(.setupGuideIntro)
        case .tapUnavailable: wizard.localizedString(.setupRestartRequiredBody)
        case .awaitingReaction: wizard.localizedString(.setupMonitoringWaitingBody)
        case .reactionObserved: wizard.localizedString(.setupMonitoringGrantedBody)
        }
    }

    private static func sourceOpacity(at referenceTime: TimeInterval) -> Double {
        let time = referenceTime.truncatingRemainder(dividingBy: 4.0)
        if time < 0.35 {
            return 1
        }
        if time < 0.55 {
            return 1 - 0.78 * smooth((time - 0.35) / 0.2)
        }
        if time < 2.0 {
            return 0.22
        }
        if time < 2.85 {
            return 0.22 + 0.78 * smooth((time - 2.0) / 0.85)
        }
        return 1
    }

    private static func smooth(_ progress: Double) -> Double {
        let value = min(max(progress, 0), 1)
        return value * value * (3 - 2 * value)
    }
}

@MainActor
private final class DragDemonstrationModel: ObservableObject {
    @Published var screenFrame: CGRect = .zero
    @Published var source: CGPoint = .zero
    @Published var target: CGPoint = .zero
    @Published var isVisible = false
}

@MainActor
private final class DragDemonstrationOverlayController {
    private let model = DragDemonstrationModel()
    private var panel: NSPanel?
    private var screenID: CGDirectDisplayID?

    func update(screen: NSScreen, source: NSPoint, target: CGPoint) {
        if panel == nil || screenID != screenNumber(screen) {
            close()
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
            screenID = screenNumber(screen)
        }
        panel?.setFrame(screen.frame, display: true)
        model.screenFrame = screen.frame
        model.source = CGPoint(x: source.x - screen.frame.minX, y: screen.frame.maxY - source.y)
        model.target = CGPoint(x: target.x - screen.frame.minX, y: screen.frame.maxY - target.y)
        model.isVisible = true
        panel?.orderFrontRegardless()
    }

    func close() {
        model.isVisible = false
        panel?.orderOut(nil)
        panel = nil
        screenID = nil
    }

    private func screenNumber(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
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
            if model.isVisible, !reduceMotion {
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
            if time >= 0.2, time < 0.56 {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay(Circle().stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5))
                    .frame(width: 22, height: 22)
                    .scaleEffect(1 - 0.18 * pressProgress)
                    .position(grabPoint)
            }
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
        let a = inverse * inverse * inverse
        let b = 3 * inverse * inverse * progress
        let c = 3 * inverse * progress * progress
        let d = progress * progress * progress
        return CGPoint(
            x: a * start.x + b * control1.x + c * control2.x + d * end.x,
            y: a * start.y + b * control1.y + c * control2.y + d * end.y
        )
    }
}

enum SystemSettingsLauncher {
    @discardableResult
    static func openInputMonitoringSettings() -> Bool {
        let modern = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
        let legacy = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        let urls = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
            ? [modern, legacy]
            : [legacy, modern]
        for string in urls {
            guard let url = URL(string: string), NSWorkspace.shared.open(url) else { continue }
            return true
        }
        return false
    }
}
