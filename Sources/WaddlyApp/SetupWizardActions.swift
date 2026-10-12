import AppKit
import UniformTypeIdentifiers

// MARK: - Actions

extension SetupWizardController {
    /// Reading and saving happen in one step: choosing a file is already the user's decision.
    /// Cancelling the picker leaves everything untouched, and "画像を変更" is always available.
    func importImage(from url: URL) {
        Task { [weak self] in
            guard let self else { return }
            guard let images = await onPreviewImage(url) else {
                // The failure alert is raised by the import path; the page itself stays put.
                renderCurrentStep()
                return
            }
            if await onConfirmImage(images) {
                importedFileName = url.lastPathComponent
                didRegisterPet = true
            }
            renderCurrentStep()
        }
    }

    @objc func showChatGPTGuide() {
        isShowingChatGPTGuide = true
        didFailCopy = false
        didAttemptCopy = false
        renderCurrentStep()
    }

    @objc func changeMethod() {
        isShowingChatGPTGuide = false
        didFailCopy = false
        didAttemptCopy = false
        renderCurrentStep()
    }

    @objc func importFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = localizedString(.setupChoosePNG)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importImage(from: url)
    }

    @objc func copyPromptAndOpenChatGPT() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        didAttemptCopy = true
        didFailCopy = !pasteboard.setString(prompt, forType: .string)
        renderCurrentStep()
        guard !didFailCopy, let url = URL(string: "https://chatgpt.com/") else { return }
        NSWorkspace.shared.open(url)
    }

    /// First attempt: ask macOS, then open the pane and the drag helper together.
    /// Opening System Settings is only correct while the permission is actually missing.
    @objc func enableMonitoring() {
        didAttemptPermission = true
        guard !isMonitoringGranted else {
            retryMonitoring()
            return
        }
        _ = requestInputMonitoringPermission()
        renderCurrentStep()
        guard !isMonitoringReady else { return }
        enterDropGuide()
    }

    /// Already granted but the keyboard is not arriving: restart the tap only.
    /// Re-opening System Settings here would loop the user straight back into the helper.
    @objc func retryMonitoring() {
        restartInputMonitoring()
        renderCurrentStep()
    }

    /// macOS only applies Input Monitoring to a fresh process, so offer the restart it asks for.
    @objc func relaunchApp() {
        leaveDropGuide()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    /// The guide is the wizard itself: open the pane, park the window next to it, and wait.
    func enterDropGuide() {
        isShowingDropGuide = true
        isShowingManualSteps = false
        // Waddly is not the active app while the user works in System Settings, and an inactive
        // app's window cannot rise above it. Floating keeps the drag source reachable.
        window?.level = .floating
        PermissionGuidePlacement.openInputMonitoringSettings()
        parkBesideSystemSettings()
        startPermissionPolling()
        renderCurrentStep()
        // System Settings activates a moment after the open call. Raise the wizard once it has
        // settled, because on a narrow screen the two windows cannot avoid overlapping and the
        // icon has to stay reachable while the settings list stays visible.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, isShowingDropGuide else { return }
            parkBesideSystemSettings()
            window?.orderFront(nil)
        }
    }

    func leaveDropGuide() {
        guard isShowingDropGuide else { return }
        isShowingDropGuide = false
        isShowingManualSteps = false
        window?.level = .normal
        stopPermissionPolling()
        renderCurrentStep()
    }

    /// Called when the settings window has appeared, and again on every poll so the window follows it.
    func parkBesideSystemSettings() {
        guard isShowingDropGuide, let window, let settings = PermissionGuidePlacement.systemSettingsWindowFrame() else {
            return
        }
        let visible = (NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main)?
            .visibleFrame
        guard let visible else { return }
        let ownWindows = NSApp.windows
            .filter { $0 !== window && $0.isVisible }
            .map(\.frame)
        let origin = PermissionGuidePlacement.origin(
            windowSize: window.frame.size,
            settings: settings,
            visible: visible,
            ownWindows: ownWindows
        )
        window.setFrameOrigin(origin)
        window.orderFront(nil)
    }

    private func startPermissionPolling() {
        stopPermissionPolling()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.hasInputMonitoringPermission() {
                    self.leaveDropGuide()
                    self.window?.center()
                    return
                }
                self.parkBesideSystemSettings()
            }
        }
        timer.tolerance = 0.1
        permissionTimer = timer
    }

    func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    @objc func openInputMonitoringSettings() {
        PermissionGuidePlacement.openInputMonitoringSettings()
    }

    @objc func toggleManualSteps() {
        isShowingManualSteps.toggle()
        renderCurrentStep()
    }

    /// Jumps back to the permission step from the completion screen.
    @objc func showMonitoringStep() {
        setStep(.monitoring)
    }

    @objc func deferMonitoring() {
        didDeferMonitoring = true
        setStep(.completed)
    }

    /// Troubleshooting stays in the window: hiding it to open System Settings lost the user.
    @objc func toggleTroubleshooting() {
        isShowingTroubleshooting.toggle()
        renderCurrentStep()
    }

    @objc func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @objc func goBack() {
        switch currentStep {
        case .pet:
            return
        case .monitoring:
            setStep(.pet)
        case .completed:
            setStep(.monitoring)
        }
    }

    @objc func goNext() {
        guard currentStep != .pet || hasImage else { return }
        guard let next = Step(rawValue: currentStep.rawValue + 1) else {
            if isMonitoringReady {
                previewPane.celebrate()
                completionPlayer.stop()
            }
            stopPermissionPolling()
            // Setup is finished, so there is nothing left to resume.
            onStepChange(nil)
            onShowOnDesktop()
            window?.close()
            return
        }
        didDeferMonitoring = false
        if next == .completed {
            completionPlayer.playLoop()
        }
        setStep(next)
    }
}
