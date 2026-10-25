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
        // Counted before the task starts, so a sample click made while this import is still decoding
        // or committing sees it instead of racing the first await.
        pendingImportCount += 1
        return Task { [weak self] in
            guard let self else { return }
            defer { pendingImportCount -= 1 }
            guard let images = await onPreviewImage(url) else {
                // A previous decode must not restore feedback after navigation or a newer attempt.
                guard importFeedbackGeneration == generation else { return }
                didFailImport = true
                announce(localizedString(.petImportErrorMessage))
                renderCurrentStep()
                return
            }
            if await onConfirmImage(images, .userFile) {
                importedFileName = url.lastPathComponent
                didRegisterPet = true
                didUseSamplePet = false
                if importFeedbackGeneration == generation {
                    didFailImport = false
                }
            }
            renderCurrentStep()
        }
    }

    /// Uses the bundled sample as the pet, without a file picker. The commit goes through the same
    /// path as an import, so the sample becomes a real, local pet image; the user stays on this
    /// step and can see which pet is active. Offered only while the store is empty and no import is
    /// pending, so it never replaces a pet the user asked for, and it never touches the saved step.
    @discardableResult
    func trySamplePet() -> Task<Void, Never> {
        // A rapid second click must not start a second write: hand back the commit already running.
        if let inFlight = sampleCommitTask {
            return inFlight
        }
        clearImportFeedback()
        let task = Task { [weak self] in
            guard let self else { return }
            defer { sampleCommitTask = nil }
            guard canTrySample, let sample = demoImages else { return }
            guard await onConfirmImage(sample, .sample) else {
                // A refusal can still change the page: another window may have committed a pet in the
                // meantime, so repaint instead of leaving the stale option list behind.
                renderCurrentStep()
                return
            }
            didUseSamplePet = true
            didRegisterPet = true
            importedFileName = nil
            renderCurrentStep()
        }
        sampleCommitTask = task
        return task
    }

    /// A real key reached the app while the guide was open. Repaints the step once, when the
    /// confirmation actually changes, so the status can move from “waiting” to “confirmed”.
    func monitoringDidObserveReaction() {
        guard currentStep == .monitoring || currentStep == .completed,
              isMonitoringReady != didRenderConfirmedReaction
        else { return }
        renderCurrentStep()
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

    // MARK: - Shared character import screen

    /// Opens the shared import screen inside the Pet step. Staging writes nothing; the existing
    /// Continue/commit path does, so setup progress and the sample rule are untouched.
    func beginCharacterImport() {
        clearImportFeedback()
        isShowingChatGPTGuide = false
        characterImportModel.reload()
        isComposingCharacter = true
        renderCurrentStep()
    }

    /// The setup shell owns commit: Continue applies the staged draft, then advances the step.
    /// A failed save stays on this step with the shared screen's inline retry and the draft intact.
    @discardableResult
    func commitCharacterImportAndContinue() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            guard await characterImportModel.apply() else {
                renderCurrentStep()
                return
            }
            importedFileName = characterImportModel.sourceName
            didRegisterPet = true
            didUseSamplePet = false
            stopEmbeddedCharacterPreview()
            isComposingCharacter = false
            goNext()
        }
    }

    /// Leaving the shared screen. A staged-but-uncommitted change asks first; an untouched screen
    /// returns to the method list immediately.
    func cancelCharacterImport() {
        guard !characterImportModel.isApplying else { return }
        guard characterImportModel.isDirty else {
            leaveCharacterImport()
            return
        }
        confirmDiscard { [weak self] in self?.leaveCharacterImport() }
    }

    /// The native picker for the shared screen. Cancelling is not an error and stages nothing.
    func chooseCharacterFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = localizedString(.setupChoosePNG)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Routes the window-wide drop: the shared screen stages, the legacy path imports directly.
    func handleWindowDrop(_ urls: [URL]) {
        guard !isMonitoringSettings else { return }
        if isComposingCharacter {
            Task { [weak self] in await self?.characterImportModel.stageFiles(at: urls) }
            return
        }
        guard let url = urls.first else { return }
        importImage(from: url)
    }

    private func leaveCharacterImport() {
        guard !characterImportModel.isApplying else { return }
        characterImportModel.discard()
        stopEmbeddedCharacterPreview()
        isComposingCharacter = false
        renderCurrentStep()
    }

    func stopEmbeddedCharacterPreview() {
        embeddedCharacterPreviewPane?.stopPlayback()
        embeddedCharacterPreviewPane = nil
    }

    private func confirmDiscard(then discard: @escaping @MainActor () -> Void) {
        guard !characterImportModel.isApplying else { return }
        guard let window else {
            discard()
            return
        }
        let alert = NSAlert()
        alert.messageText = localizedString(.characterDiscardTitle)
        alert.informativeText = localizedString(.characterDiscardMessage)
        alert.alertStyle = .warning
        alert.addButton(withTitle: localizedString(.characterDiscardConfirm))
        alert.addButton(withTitle: localizedString(.characterCancel))
        presenter.presentAlert(alert, window) { response in
            guard response == .alertFirstButtonReturn else { return }
            discard()
        }
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
