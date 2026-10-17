import AppKit
import UniformTypeIdentifiers

// MARK: - Actions

extension SetupWizardController {
    /// Reading and saving happen in one step: choosing a file is already the user's decision.
    /// Cancelling the picker leaves everything untouched, and "画像を変更" is always available.
    @discardableResult
    func importImage(from url: URL) -> Task<Void, Never> {
        clearImportFeedback()
        let generation = importFeedbackGeneration
        return Task { [weak self] in
            guard let self else { return }
            guard let images = await onPreviewImage(url) else {
                // A previous decode must not restore feedback after navigation or a newer attempt.
                guard importFeedbackGeneration == generation else { return }
                didFailImport = true
                announce(localizedString(.petImportErrorMessage))
                renderCurrentStep()
                return
            }
            if await onConfirmImage(images) {
                importedFileName = url.lastPathComponent
                didRegisterPet = true
                if importFeedbackGeneration == generation {
                    didFailImport = false
                }
            }
            renderCurrentStep()
        }
    }

    /// Invalidates pending feedback without cancelling image commits already in progress.
    func clearImportFeedback() {
        importFeedbackGeneration = UUID()
        didFailImport = false
    }

    @objc func showChatGPTGuide() {
        isShowingChatGPTGuide = true
        promptFeedback = nil
        clearImportFeedback()
        renderCurrentStep()
    }

    @objc func changeMethod() {
        isShowingChatGPTGuide = false
        promptFeedback = nil
        clearImportFeedback()
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
        pasteboard.clearContents()
        guard pasteboard.setString(prompt, forType: .string) else {
            reportPromptFeedback(.copyFailed)
            return
        }
        guard let url = URL(string: "https://chatgpt.com/") else {
            reportPromptFeedback(.copied)
            return
        }
        // The copy already succeeded, so a browser failure is its own truthful message.
        reportPromptFeedback(openBrowser(url) ? .copied : .openFailed)
    }

    /// Sets the inline result, announcing only a failure so VoiceOver hears the reason once.
    private func reportPromptFeedback(_ feedback: PromptActionFeedback) {
        promptFeedback = feedback
        if promptFeedbackIsError, let key = promptFeedbackKey {
            announce(localizedString(key))
        }
        renderCurrentStep()
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
            refreshGuideFollowing()
            applyGuideWindowLevel()
            renderCurrentStep()
            if !isShowingGuide {
                window?.level = .normal
                window?.center()
            }
        }
        permission.onTick = { [weak self] in
            self?.parkBesideSystemSettings()
        }
    }

    /// The guide parks next to System Settings. Waddly is not the active app there, and an inactive
    /// app's window cannot sit above it, so guiding is the one time the window floats.
    func applyGuideWindowLevel() {
        window?.level = isShowingGuide ? .floating : .normal
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
        window.orderFrontRegardless()
    }

    /// Jumps back to the permission step from the completion screen.
    @objc func showMonitoringStep() {
        setStep(.monitoring)
    }

    @objc func openInputMonitoringSettings() {
        PermissionGuidePlacement.openInputMonitoringSettings()
    }

    @objc func toggleManualSteps() {
        permission.toggleManualSteps()
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
