import AppKit
import WaddlyCore

extension AppDelegate {
    var permissionService: PermissionService {
        if let existing = permissionServiceStorage {
            return existing
        }
        let service = PermissionService(
            hasPermission: { [weak self] in self?.monitor.permissionGranted ?? false },
            isReceivingKeys: { [weak self] in
                guard let self else { return false }
                // Pausing stops the tap on purpose; that is not a permission failure.
                return isPaused || monitor.isRunning
            },
            // A key confirms reactions only while the tap that saw it is still running. Pausing stops
            // the tap, so a confirmation from before the pause must not outlive it.
            hasObservedReaction: { [weak self] in
                guard let self else { return false }
                return AppDelegate.reactionIsConfirmed(
                    tapRunning: monitor.isRunning,
                    observedKeyEvent: monitor.hasObservedKeyEvent
                )
            },
            requestAccess: { [weak self] in
                guard let self else { return false }
                let granted = monitor.requestPermission()
                if granted, !isPaused {
                    startMonitoring()
                }
                return granted
            },
            restartTap: { [weak self] in
                guard let self else { return }
                monitor.stop()
                if !isPaused {
                    startMonitoring()
                }
            }
        )
        permissionServiceStorage = service
        return service
    }

    /// A key confirms reactions only while the tap that saw it is still running. Pausing stops the
    /// tap, so a confirmation from before the pause must not outlive it. Pure so the rule is testable.
    nonisolated static func reactionIsConfirmed(tapRunning: Bool, observedKeyEvent: Bool) -> Bool {
        tapRunning && observedKeyEvent
    }

    @objc func showSetupWizard() {
        if setupWizardController == nil {
            setupWizardController = makeSetupWizardController()
        }
        // Opening the wizard must also make monitoring live, otherwise "granted but not receiving"
        // would be reported as "restart required" when the tap simply had not been started yet.
        startMonitoringIfPossible()
        guard let controller = setupWizardController, let window = controller.window else { return }
        // The status shown on step 2 depends on the tap above, and showWindow does not redraw.
        controller.renderCurrentStep()
        let wasVisible = window.isVisible
        presenter.activate()
        controller.moveWindowProgrammatically {
            controller.showWindow(nil)
            // Re-assert the designed size; a restored frame must never win here.
            window.setContentSize(SetupMetrics.contentSize)
            // Only a freshly shown window is centered. Re-centering an already open guide would
            // fight its parked position and look like a user move to `GuideFollowing`.
            if !wasVisible {
                window.center()
            }
        }
    }

    private func makeSetupWizardController() -> SetupWizardController {
        SetupWizardController(
            localization: localization,
            onPreviewImage: { [weak self] in await self?.previewPetImage(from: $0) },
            onConfirmImage: { [weak self] images, source in
                await self?.confirmPetImage(images, source: source) ?? false
            },
            // The shared screen reports persistence failures inline and keeps the draft for retry, so
            // this path never raises the legacy save alert.
            onCommitCharacter: { [weak self] images in
                await self?.commitCharacterImages(images) ?? .rejected
            },
            currentPetImages: { [weak self] in self?.petImages ?? PetImageSet() },
            permission: permissionService,
            presenter: presenter,
            savedStep: settings.setupStep,
            onStepChange: { [weak settings] step in settings?.setupStep = step },
            onShowOnDesktop: { [weak self] in self?.revealPetOnDesktop() },
            onClose: { [weak self] in self?.handleSetupWizardClose() }
        )
    }

    /// Records the finished setup and restarts monitoring when the wizard closes.
    private func handleSetupWizardClose() {
        if hasCompletePetImageSet {
            settings.setupWizardSeen = true
        } else {
            settings.removeSetupWizardSeen()
        }
        setupWizardController = nil
        guard hasCompletePetImageSet, monitor.permissionGranted, !isPaused else { return }
        startMonitoring()
    }

    private func startMonitoringIfPossible() {
        guard hasCompletePetImageSet, monitor.permissionGranted, !isPaused, !monitor.isRunning else { return }
        startMonitoring()
    }
}
