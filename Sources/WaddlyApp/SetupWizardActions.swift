import AppKit
import UniformTypeIdentifiers

// MARK: - Actions

extension SetupWizardController {
    /// A real key both confirms readiness and drives the matching preview animation.
    func monitoringDidObserveReaction(isEnter: Bool) {
        guard currentStep == .monitoring || currentStep == .completed else { return }
        if isMonitoringReady != didRenderConfirmedReaction {
            renderCurrentStep()
        }
        if currentStep == .monitoring, isMonitoringReady {
            previewPane.reactToKey(isEnter: isEnter)
        }
    }

    // MARK: - Shared character import screen

    func beginCharacterImport() {
        characterImportModel.reload()
        renderCurrentStep()
    }

    @discardableResult
    func commitCharacterImportAndContinue() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            guard await characterImportModel.apply() else {
                renderCurrentStep()
                return
            }
            stopEmbeddedCharacterPreview()
            goNext()
        }
    }

    func chooseCharacterFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = localizedString(.setupChoosePNG)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func handleWindowDrop(_ urls: [URL]) {
        guard isComposingCharacter else { return }
        Task { [weak self] in await self?.characterImportModel.stageFiles(at: urls) }
    }

    func stopEmbeddedCharacterPreview() {
        embeddedCharacterPreviewPane?.stopPlayback()
        embeddedCharacterPreviewPane = nil
    }

    /// First attempt: ask macOS, then turn the wizard into the drag guide.
    @objc func enableMonitoring() {
        permission.request()
    }

    /// Granted but the keyboard is not arriving: restart the tap only. The service guarantees this
    /// never reopens System Settings, which would only loop the user back into the guide.
    @objc func retryMonitoring() {
        permission.retryTap()
    }

    /// macOS only applies Input Monitoring to a fresh process, so offer the restart it asks for.
    @objc func relaunchApp() {
        permission.stop()
        relaunch()
    }

    /// Opens a new instance, then quits this one. The saved step is the resume signal, so the new
    /// process comes back to the same setup page instead of leaving the user half-configured.
    static func performRelaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    /// Wires the service to this window: re-render on every state change, follow Settings on ticks.
    func bindPermission() {
        permission.onUpdate = { [weak self] in
            guard let self else { return }
            // Following has to be refreshed before the window is parked or centred.
            refreshGuideFollowing()
            renderCurrentStep()
        }
        permission.onTick = { [weak self] in
            self?.parkBesideSystemSettings()
        }
    }

    /// The guide floats and follows System Settings on the one page it belongs to. Entering that page
    /// shrinks the window to the compact guide and parks it; leaving it restores the designed window
    /// and centres it again, so a later page is never left in the narrow frame.
    func updateGuidePresentation() {
        window?.level = isShowingGuide ? .floating : .normal
        let compact = isCompactGuide
        // Only a real transition touches the frame: the polling tick owns keeping the parked window
        // beside System Settings, and re-showing an open guide must not move it (#79).
        guard compact != appliedCompactGuide else { return }
        appliedCompactGuide = compact
        window?.contentMinSize = contentSize
        window?.setContentSize(contentSize)
        if compact {
            // The preview column is gone while guiding, so the player would animate an off-screen
            // view for as long as the guide stays open.
            previewPane.stopPlayback()
            parkBesideSystemSettings()
        } else {
            window?.center()
        }
    }

    /// Called by the service's ticks, and once when the guide opens.
    func parkBesideSystemSettings() {
        guard isFollowingSystemSettings,
              isShowingGuide,
              let window,
              let settings = PermissionGuidePlacement.systemSettingsWindowFrame(),
              let visible = (NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main)?
              .visibleFrame
        else { return }
        let ownWindows = NSApp.windows
            .filter { $0 !== window && $0.isVisible }
            .map(\.frame)
        let origin = PermissionGuidePlacement.origin(
            windowSize: window.frame.size,
            settings: settings,
            visible: visible,
            ownWindows: ownWindows
        )
        moveWindowProgrammatically {
            window.setFrameOrigin(origin)
        }
        presenter.reveal(window)
    }

    /// Jumps back to the permission step from the completion screen.
    @objc func showMonitoringStep() {
        setStep(.monitoring)
    }

    @objc func openInputMonitoringSettings() {
        PermissionGuidePlacement.openInputMonitoringSettings()
    }

    @objc func deferMonitoring() {
        permission.deferSetup()
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
        if isMonitoringSettings {
            close()
            return
        }
        guard currentStep != .pet || hasImage else { return }
        guard currentStep != .monitoring || isMonitoringReady else { return }
        guard let next = Step(rawValue: currentStep.rawValue + 1) else {
            if isMonitoringReady {
                previewPane.celebrate()
            }
            permission.stop()
            // Setup is finished, so there is nothing left to resume.
            onStepChange(nil)
            onShowOnDesktop()
            window?.close()
            return
        }
        setStep(next)
    }
}
