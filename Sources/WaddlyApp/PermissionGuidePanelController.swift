import AppKit
import SwiftUI

/// A non-activating companion still accepts keyboard focus when the user clicks it. Key equivalents
/// must be handled by the panel itself because another application may own the menu bar.
@MainActor
final class PermissionGuidePanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isClose = event.type == .keyDown
            && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "w"
        guard isClose else { return super.performKeyEquivalent(with: event) }
        performClose(nil)
        return true
    }
}

@MainActor
final class PermissionGuidePanelController: NSWindowController, NSWindowDelegate {
    private weak var wizard: SetupWizardController?
    private let overlay = DragDemonstrationOverlayController()
    private var settingsTimer: Timer?
    private weak var sourceView: DraggableAppIconView?
    private var following = GuideFollowing()
    private var isMovingProgrammatically = false
    var isFollowingSystemSettings: Bool {
        following.isActive
    }

    init(wizard: SetupWizardController) {
        self.wizard = wizard
        let size = SetupMetrics.permissionGuideSize
        let panel = PermissionGuidePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = wizard.localizedString(.setupSetUpMonitoring)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // Clicking the guide must give it keyboard focus even though it has no text fields.
        panel.becomesKeyOnlyIfNeeded = false
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
            onClose: { [weak panel] in panel?.performClose(nil) },
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
        if panel.isVisible {
            panel.orderFrontRegardless()
            return
        }
        following.begin()
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
        if !wizard.permission.isGranted, !wizard.permission.isGuiding {
            wizard.permission.beginGuiding()
        } else if wizard.permission.readiness == .tapUnavailable {
            wizard.permission.retryTap()
        }
    }

    func stop() {
        settingsTimer?.invalidate()
        settingsTimer = nil
        overlay.close()
        window?.orderOut(nil)
        window?.contentView = nil
    }

    func windowDidMove(_ notification: Notification) {
        guard !isMovingProgrammatically, let window else { return }
        following.recordMove(to: window.frame.origin)
    }

    func windowWillClose(_ notification: Notification) {
        guard let wizard else { return }
        stop()
        wizard.permission.stop()
        wizard.permissionGuidePanelController = nil
        wizard.window?.close()
    }

    func openSettings() {
        guard let wizard else { return }
        if wizard.permission.isGuiding || wizard.permission.isGranted {
            wizard.permission.openSettingsForTroubleshooting()
        } else {
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
                movePanel(to: PermissionGuidePlacement.clamped(origin, size: panel.frame.size, into: visible))
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
        movePanel(to: origin)
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

    private func movePanel(to origin: NSPoint) {
        guard following.isActive, let panel = window else { return }
        isMovingProgrammatically = true
        panel.setFrameOrigin(origin)
        following.recordProgrammaticMove(to: panel.frame.origin)
        isMovingProgrammatically = false
    }

    private func fitToContent() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = window,
                  let hosting = panel.contentView as? NSHostingView<PermissionGuidePanelView>
            else { return }
            let width = SetupMetrics.permissionGuideSize.width
            let height = hosting.fittingSize.height
            guard height > 0 else { return }
            isMovingProgrammatically = true
            panel.setContentSize(NSSize(width: width, height: height))
            following.recordProgrammaticMove(to: panel.frame.origin)
            isMovingProgrammatically = false
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
    let onClose: () -> Void
    let onNext: () -> Void
    let onRestart: () -> Void
    let onReadinessChanged: () -> Void
    let onRealDragStarted: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            if wizard.monitoringReadiness == .permissionMissing {
                TimelineView(.animation(
                    minimumInterval: 1.0 / 20.0,
                    paused: reduceMotion || wizard.isMonitoringDragDemoStopped
                )) { context in
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
                Button(
                    wizard.localizedString(.setupOpenSystemSettings),
                    systemImage: "gearshape",
                    action: onOpenSettings
                )
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
                Button(wizard.localizedString(.setupOpenSystemSettings), action: onOpenSettings)
                    .buttonStyle(.bordered)
            case .awaitingReaction, .reactionObserved:
                Button(wizard.localizedString(.setupNotWorking)) {
                    wizard.toggleTroubleshooting()
                }
                .buttonStyle(.bordered)
                if wizard.isShowingTroubleshooting {
                    Text(wizard.localizedString(.setupTroubleshootingBody))
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(wizard.localizedString(.setupRestartNow), action: onRestart)
                        .buttonStyle(.bordered)
                    Button(wizard.localizedString(.setupOpenSystemSettings), action: onOpenSettings)
                        .buttonStyle(.bordered)
                }
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
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(wizard.localizedString(.setupLater), action: onLater)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: SetupMetrics.permissionGuideSize.width)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: onClose)
        .onChange(of: wizard.monitoringReadiness) { _, _ in onReadinessChanged() }
        .onChange(of: wizard.isShowingTroubleshooting) { _, _ in onReadinessChanged() }
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
