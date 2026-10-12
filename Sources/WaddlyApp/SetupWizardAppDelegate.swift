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

    @objc func showSetupWizard() {
        if setupWizardController == nil {
            setupWizardController = SetupWizardController(
                localization: localization,
                onPreviewImage: { [weak self] in await self?.previewPetImage(from: $0) },
                onConfirmImage: { [weak self] in await self?.confirmPetImage($0) ?? false },
                currentPetImages: { [weak self] in self?.petImages ?? PetImageSet() },
                permission: permissionService,
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
