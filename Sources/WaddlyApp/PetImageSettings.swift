import AppKit
import SwiftUI
import WaddlyCore

extension AppDelegate {
    func loadSavedPetImage() async {
        guard let directory = petImagesDirectoryURL else { return }
        let manifest = settings.petImageFiles
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try autoreleasepool {
                    let loaded = try PetImageStorage(directory: directory).load(manifest)
                    return (loaded.0, loaded.1, PetSpriteSheetImporter.thumbnails(for: loaded.0))
                }
            }.value
            guard !isShuttingDown else { return }
            storedImageFiles = loaded.1
            if !manifest.isEmpty {
                importedImages = loaded.0
                imageThumbnails = loaded.2
            }
        } catch {
            imageLoadFailed = true
            storedImageFiles = manifest
            await showImageSaveError(error)
        }
    }

    func importPetImage(from url: URL) async -> Bool {
        await queueImageUpdate { await self.importPetImageInOrder(from: url) }
    }

    private func importPetImageInOrder(from url: URL) async -> Bool {
        let prepared = await Task.detached(priority: .userInitiated) {
            autoreleasepool { () -> (PetImageSet, NSImage)? in
                guard let data = PetSpriteSheetImporter.readPNG(from: url),
                      let images = PetSpriteSheetImporter.frames(from: data),
                      let preview = PetSpriteSheetImporter.preview(from: data) else { return nil }
                return (images, preview)
            }
        }.value
        guard !isShuttingDown else { return false }
        guard let (newImages, preview) = prepared else {
            await showPetImageImportError()
            return false
        }
        guard await confirmPetImageImport(preview, cellSize: Int(newImages[.idle][0].size.width)) else { return false }
        do {
            try await persistPetImages(newImages, resetActivity: true)
        } catch {
            await showImageSaveError(error)
            return false
        }
        imageLoadFailed = false
        return true
    }

    /// Reads a sheet for review only. Nothing is written until `confirmPetImage` is called,
    /// so the wizard can show the nine cells before anything is committed.
    func previewPetImage(from url: URL) async -> PetImageSet? {
        let images = await Task.detached(priority: .userInitiated) {
            autoreleasepool { () -> PetImageSet? in
                guard let data = PetSpriteSheetImporter.readPNG(from: url) else { return nil }
                return PetSpriteSheetImporter.frames(from: data)
            }
        }.value
        guard !isShuttingDown else { return nil }
        guard let images else {
            await showPetImageImportError()
            return nil
        }
        return images
    }

    /// Commits a set the user already reviewed.
    func confirmPetImage(_ images: PetImageSet) async -> Bool {
        await queueImageUpdate { await self.confirmPetImageInOrder(images) }
    }

    private func confirmPetImageInOrder(_ images: PetImageSet) async -> Bool {
        do {
            try await persistPetImages(images, resetActivity: true)
        } catch {
            await showImageSaveError(error)
            return false
        }
        imageLoadFailed = false
        return true
    }

    func imageSetDidChange(resetActivity: Bool = false) {
        animationSettingsModel?.setThumbnails(currentThumbnails())
        guard hasCompletePetImageSet else {
            panel.orderOut(nil)
            animationController.imageSetDidChange(resetActivity: resetActivity)
            return
        }
        panel.orderFrontRegardless()
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
        } else {
            await showAlert(.imagesSaveErrorTitle, .imagesSaveErrorMessage)
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
        NSApp.activate(ignoringOtherApps: true)
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: parent) { response in
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
            window.minSize = NSSize(width: 620, height: 640)
            window.isReleasedWhenClosed = false

            imageSettingsWindow = window
            window.delegate = self
            window.center()
            window.contentView = makeImageSettingsContent()
        }
        NSApp.activate(ignoringOtherApps: true)
        imageSettingsWindow?.makeKeyAndOrderFront(nil)
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
