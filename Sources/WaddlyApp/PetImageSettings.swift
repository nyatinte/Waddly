import AppKit
import SwiftUI
import WaddlyCore

extension AppDelegate {
    /// Restore the last committed frame set through the store.
    ///
    /// The store treats the on-disk manifest as authoritative and keeps edits blocked when it
    /// cannot be read or decoded; the alert stays here.
    func loadSavedPetImage() async {
        do {
            try await imageStore.restore()
        } catch {
            await showImageSaveError(error)
        }
    }

    func importPetImage(from url: URL) async -> Bool {
        let outcome = await imageStore.importPetImage(from: url) { [weak self] preview, cellSize in
            await self?.confirmPetImageImport(preview, cellSize: cellSize) ?? false
        }
        switch outcome {
        case .imported:
            return true
        case .invalid:
            await showPetImageImportError()
            return false
        case let .failed(error):
            await showImageSaveError(error)
            return false
        case .cancelled, .aborted:
            return false
        }
    }

    /// Reads a sheet without writing. The wizard calls `confirmPetImage` immediately on success;
    /// a failed read returns `nil` and leaves the saved set untouched. A read failure returns
    /// `nil`; the wizard explains it in place instead of raising a separate alert.
    func previewPetImage(from url: URL) async -> PetImageSet? {
        let images = await Task.detached(priority: .userInitiated) {
            autoreleasepool { () -> PetImageSet? in
                guard let data = PetSpriteSheetImporter.readPNG(from: url) else { return nil }
                return PetSpriteSheetImporter.frames(from: data)
            }
        }.value
        guard !isShuttingDown else { return nil }
        return images
    }

    /// Commits a set the user already reviewed.
    func confirmPetImage(_ images: PetImageSet) async -> Bool {
        switch await imageStore.confirmPetImage(images) {
        case .confirmed:
            return true
        case let .failed(error):
            await showImageSaveError(error)
            return false
        case .aborted:
            return false
        }
    }

    func imageSetDidChange(resetActivity: Bool = false) {
        animationSettingsModel?.setThumbnails(currentThumbnails())
        guard hasCompletePetImageSet else {
            presenter.hide(panel)
            animationController.imageSetDidChange(resetActivity: resetActivity)
            return
        }
        presenter.reveal(panel)
        animationController.imageSetDidChange(resetActivity: resetActivity)
    }

    private func thumbnails(for category: PetImageCategory) -> [NSImage] {
        petImages[category].map { imageThumbnails[ObjectIdentifier($0)] ?? $0 }
    }

    /// Snapshots the current images as thumbnails for the SwiftUI model, keeping the editor in sync
    /// with the pet set while it is open.
    private func currentThumbnails() -> [PetImageCategory: [AnimationSettingsThumbnail]] {
        var result: [PetImageCategory: [AnimationSettingsThumbnail]] = [:]
        for category in PetImageCategory.allCases {
            result[category] = thumbnails(for: category).map(AnimationSettingsThumbnail.init)
        }
        return result
    }

    private func showPetImageImportError() async {
        await showAlert(.petImportErrorTitle, .petImportErrorMessage)
    }

    func showImageSaveError(_ error: Error) async {
        guard !isShuttingDown else { return }
        if error is PetImageStorageError {
            await showAlert(.imagesErrorTitle, .imagesMemoryLimit)
        } else if (error as? PetImageManifestError) == .unreadable {
            await showAlert(.imagesReadErrorTitle, .imagesReadErrorMessage)
        } else {
            await showAlert(.imagesSaveErrorTitle, .imagesSaveErrorMessage)
        }
    }

    /// Report why an edit is blocked. The recorded load failure keeps a memory-budget or commit
    /// problem from being misreported as an unreadable image list.
    func showImageLoadError() async {
        if let imageLoadError {
            await showImageSaveError(imageLoadError)
        } else {
            await showAlert(.imagesReadErrorTitle, .imagesReadErrorMessage)
        }
    }

    func showAlert(_ titleKey: LocalizationKey, _ messageKey: LocalizationKey) async {
        let alert = NSAlert()
        alert.messageText = localizedString(titleKey)
        alert.informativeText = localizedString(messageKey)
        alert.alertStyle = .warning
        _ = await presentImageAlertWithDefaultParent(alert)
    }

    private func confirmPetImageImport(_ preview: NSImage, cellSize: Int) async -> Bool {
        guard let parent = imageAlertParent() else { return false }
        let alert = NSAlert()
        alert.messageText = localizedString(.petPreviewTitle)
        alert.informativeText = localizedString(.petPreviewPrompt)
        alert.alertStyle = .informational
        alert.accessoryView = SpriteSheetPreviewAccessory(
            preview: preview,
            cellSize: cellSize,
            displaySize: displaySize,
            localization: localization,
            prefersDarkBackground: parent.isUsingDarkAppearance
        )
        alert.addButton(withTitle: localizedString(.petImportConfirm))
        alert.addButton(withTitle: localizedString(.commonCancel))
        return await presentImageAlert(alert, in: parent) == .alertFirstButtonReturn
    }

    private func imageAlertParent() -> NSWindow? {
        guard !isShuttingDown else { return nil }
        let activeWindow = [imageSettingsWindow, setupWizardController?.window].compactMap(\.self)
            .first(where: \.isKeyWindow)
        if let window = activeWindow {
            return window
        }
        if let window = imageSettingsWindow, window.isVisible {
            return window
        }
        if let window = setupWizardController?.window, window.isVisible {
            return window
        }
        if hasCompletePetImageSet {
            return panel
        }
        showSetupWizard()
        return setupWizardController?.window
    }

    private func presentImageAlertWithDefaultParent(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        guard let parent = imageAlertParent() else { return .cancel }
        return await presentImageAlert(alert, in: parent)
    }

    private func presentImageAlert(_ alert: NSAlert, in parent: NSWindow) async -> NSApplication.ModalResponse {
        guard !isShuttingDown else { return .cancel }
        presenter.activate()
        return await withCheckedContinuation { continuation in
            presenter.presentAlert(alert, parent) { response in
                continuation.resume(returning: response)
            }
        }
    }

    @objc func showImageSettings() {
        if imageSettingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = localizedString(.imagesWindowTitle)
            // Content minimum, not frame minimum: `minSize` is a frame height and would fall short of
            // the four rows plus instructions once the title bar is removed, clipping the last row.
            window.contentMinSize = AnimationSettingsMetrics.contentMinSize
            window.isReleasedWhenClosed = false

            imageSettingsWindow = window
            window.delegate = self
            window.center()
            window.contentView = makeImageSettingsContent()
        }
        presenter.activate()
        if let window = imageSettingsWindow {
            presenter.focus(window)
        }
    }

    func refreshImageSettingsLocalization() {
        guard let window = imageSettingsWindow else { return }
        window.title = localizedString(.imagesWindowTitle)
        animationSettingsModel?.refreshLocalization()
    }

    private func makeImageSettingsContent() -> NSView {
        let model = makeAnimationSettingsModel()
        animationSettingsModel = model
        return NSHostingView(rootView: AnimationSettingsView(model: model))
    }

    private func makeAnimationSettingsModel() -> AnimationSettingsModel {
        let model = AnimationSettingsModel(
            thumbnailsByCategory: currentThumbnails(),
            localization: localization
        )
        model.onAdd = { [weak self] category in self?.chooseImages(for: category) }
        model.onDrop = { [weak self] category, urls in self?.addImages(urls, to: category) }
        model.onRemove = { [weak self] category, index in
            _ = self?.removeImage(at: index, from: category)
        }
        model.onMove = { [weak self] category, source, destination in
            _ = self?.moveImage(from: source, to: destination, in: category)
        }
        return model
    }

    func closeImageSettingsWindow() {
        // Drop the first responder before the content so the window does not keep the hosting view
        // (or any of its controls) alive through the responder chain.
        imageSettingsWindow?.makeFirstResponder(nil)
        imageSettingsWindow?.contentView = nil
        imageSettingsWindow?.delegate = nil
        imageSettingsWindow = nil
        animationSettingsModel = nil
    }

    private func chooseImages(for category: PetImageCategory) {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.png]
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.prompt = localizedString(.imagesAdd)
        guard picker.runModal() == .OK else { return }
        addImages(picker.urls, to: category)
    }
}
