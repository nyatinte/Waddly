import AppKit
import WaddlyCore

extension NSWindow {
    var isUsingDarkAppearance: Bool {
        switch effectiveAppearance.name {
        case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
            true
        default:
            false
        }
    }
}

extension AppDelegate {
    func buildPanel() {
        applyPetWindowLevel()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        // The pet is always on screen and never switched to, so it does not belong in the Window menu.
        panel.isExcludedFromWindowsMenu = true
        panel.delegate = self

        petView.image = petImages[.idle].first
        petView.imageScaling = .scaleProportionallyUpOrDown
        petView.wantsLayer = true
        petView.autoresizingMask = [.width, .height]
        panel.contentView = petView
        applyPetAccessibility()

        if let saved = settings.panelOrigin, saved.count == 2 {
            panel.setFrameOrigin(clampedOrigin(NSPoint(x: saved[0], y: saved[1])))
        } else {
            placeAtDefaultPosition()
        }
        if hasCompletePetImageSet {
            revealPet()
        }
    }

    /// The pet's window level and Space behaviour live in one place, so every reveal path and every
    /// re-ordering sees the same panel. The pet deliberately never carries `.fullScreenAuxiliary`: a
    /// fullscreen app covers it, and system UI such as the menu bar and Spotlight stays above it.
    func applyPetWindowLevel() {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    /// The pet is the app's only always-visible surface, so VoiceOver and accessibility tooling have
    /// to be able to name it even though the panel is borderless, has no title bar, and never becomes
    /// key. Reapplied on launch and after a language change.
    func applyPetAccessibility() {
        panel.setAccessibilityTitle(localizedString(.a11yPetWindow))
        panel.setAccessibilitySubrole(.floatingWindow)
        petView.setAccessibilityElement(true)
        petView.setAccessibilityRole(.image)
        petView.setAccessibilityLabel(localizedString(.a11yPet))
        petView.setAccessibilityHelp(localizedString(.a11yPetHelp))
    }

    /// Reapplies the level before ordering the pet front, so a stale level cannot survive a reveal.
    func revealPet() {
        applyPetWindowLevel()
        presenter.reveal(panel)
    }

    /// The same reapplication for the arrival fade.
    func revealPetFadingIn() {
        applyPetWindowLevel()
        presenter.revealFadingIn(panel, 0.4)
    }

    /// Another app's floating-level panel can be ordered in front of the pet while that app is
    /// active, so the pet watches app activation and Space switches and puts itself back on top.
    /// The panel is non-activating, so this never takes focus or a click.
    func startKeepingPetInFront() {
        guard !isKeepingPetInFront else { return }
        isKeepingPetInFront = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(appDidActivateElsewhere(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    func stopKeepingPetInFront() {
        guard isKeepingPetInFront else { return }
        isKeepingPetInFront = false
        keepInFrontWorkItem?.cancel()
        keepInFrontWorkItem = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc func appDidActivateElsewhere(_ notification: Notification) {
        keepPetInFront()
        reapplyAfterFrontAppSettles()
    }

    @objc func activeSpaceDidChange(_ notification: Notification) {
        keepPetInFront()
        reapplyAfterFrontAppSettles()
    }

    /// The activating app can order its own floating panels just after the notification, so the pet
    /// checks once more after the activation settles. This is still a non-activating re-order.
    private func reapplyAfterFrontAppSettles() {
        guard isKeepingPetInFront else { return }
        keepInFrontWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.keepPetInFront()
        }
        keepInFrontWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Re-orders the pet above other apps' windows without activating it. Skipped while there is no
    /// pet to show, so setup cannot flash an empty panel.
    func keepPetInFront() {
        guard hasCompletePetImageSet else { return }
        revealPet()
    }

    func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        PetWindowPlacement.clampedOrigin(
            origin,
            size: panel.frame.size,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            mainVisibleFrame: NSScreen.main?.visibleFrame
        )
    }

    /// Pulls the pet back onto a screen that still exists after the display configuration changes.
    @objc func screenParametersDidChange(_ notification: Notification) {
        panel.setFrameOrigin(clampedOrigin(panel.frame.origin))
        saveOrigin()
    }

    func saveOrigin() {
        let origin = panel.frame.origin
        settings.panelOrigin = [origin.x, origin.y]
    }

    /// Fades the pet in when setup hands it over, so the first appearance reads as an arrival.
    func revealPetOnDesktop() {
        guard hasCompletePetImageSet else { return }
        // Reduced motion, or any interrupted animation, must never leave the pet invisible.
        guard !MotionPreference.isReduced else {
            panel.alphaValue = 1
            revealPet()
            return
        }
        revealPetFadingIn()
    }

    private func placeAtDefaultPosition() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(x: visible.maxX - panel.frame.width - 18, y: visible.minY + 18)
        panel.setFrameOrigin(origin)
        saveOrigin()
    }

    /// Post-setup character management. Opens the shared import screen on the committed pet.
    @objc func showChangeCharacter() {
        if characterImportWindowController == nil {
            characterImportWindowController = CharacterImportWindowController(
                model: CharacterImportModel(
                    currentImages: { [weak self] in self?.petImages ?? PetImageSet() },
                    commit: { [weak self] images in
                        await self?.commitCharacterImages(images) ?? .rejected
                    }
                ),
                localization: localization,
                presenter: presenter,
                onClose: { [weak self] in self?.characterImportWindowController = nil }
            )
        }
        characterImportWindowController?.focus()
    }
}
