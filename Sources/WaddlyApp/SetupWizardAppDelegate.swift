import AppKit
import WaddlyCore

extension AppDelegate {
    @objc func showSetupWizard() {
        if setupWizardController == nil {
            setupWizardController = SetupWizardController(
                localization: localization,
                onPreviewImage: { [weak self] in await self?.previewPetImage(from: $0) },
                onConfirmImage: { [weak self] in await self?.confirmPetImage($0) ?? false },
                currentPetImages: { [weak self] in self?.petImages ?? PetImageSet() },
                hasInputMonitoringPermission: { [weak self] in self?.monitor.permissionGranted ?? false },
                isInputMonitoringActive: { [weak self] in
                    guard let self else { return false }
                    // Pausing stops the tap on purpose; that is not a permission failure.
                    return isPaused || monitor.isRunning
                },
                requestInputMonitoringPermission: { [weak self] in
                    guard let self else { return false }
                    let granted = monitor.requestPermission()
                    if granted, !isPaused {
                        startMonitoring()
                    }
                    return granted
                },
                restartInputMonitoring: { [weak self] in
                    guard let self else { return }
                    monitor.stop()
                    if !isPaused {
                        startMonitoring()
                    }
                },
                savedStep: settings.setupStep,
                onStepChange: { [weak settings] step in settings?.setupStep = step },
                onShowOnDesktop: { [weak self] in self?.revealPetOnDesktop() },
                onClose: { [weak self] in
                    guard let self else { return }
                    if !hasCompletePetImageSet {
                        settings.removeSetupWizardSeen()
                    } else {
                        settings.setupWizardSeen = true
                    }
                    if hasCompletePetImageSet, monitor.permissionGranted, !isPaused {
                        startMonitoring()
                    }
                }
            )
        }
        // Opening the wizard must also make monitoring live, otherwise "granted but not receiving"
        // would be reported as "restart required" when the tap simply had not been started yet.
        if hasCompletePetImageSet, monitor.permissionGranted, !isPaused, !monitor.isRunning {
            startMonitoring()
        }
        // The status shown on step 2 depends on the tap above, and showWindow does not redraw.
        setupWizardController?.renderCurrentStep()
        NSApp.activate(ignoringOtherApps: true)
        setupWizardController?.showWindow(nil)
        // Re-assert the designed size; a restored frame must never win here.
        setupWizardController?.window?.setContentSize(SetupMetrics.contentSize)
        setupWizardController?.window?.center()
    }
}
