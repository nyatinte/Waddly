import AppKit
import SwiftUI
import WaddlyCore

extension AppDelegate {
    /// Restore the last committed frame set, treating the on-disk manifest as authoritative.
    ///
    /// When the manifest is missing, the legacy `UserDefaults` mirror is committed to disk before
    /// the reconciling sweep so the frames it still names are protected. A manifest that cannot be
    /// read leaves the app read-only: edits and deletion stay blocked until images are imported
    /// again. Reconciliation runs off the main actor, serialized by the image queue, and only when
    /// the manifest fully materialized and the mirror still agrees with it; disagreement can mean
    /// another build wrote frames after this manifest, so those frames stay until a deliberate save.
    func loadSavedPetImage() async {
        guard let directory = petImagesDirectoryURL else { return }
        let storage = PetImageStorage(directory: directory)
        let legacyFiles = settings.petImageFiles
        do {
            let restored = try await Task.detached(priority: .userInitiated) {
                try autoreleasepool { () -> RestoredPetImages in
                    let manifest = try committedOrMigratedManifest(storage, legacy: legacyFiles)
                    let loaded = try storage.load(manifest)
                    return RestoredPetImages(
                        manifest: manifest,
                        images: loaded.0,
                        files: loaded.1,
                        thumbnails: PetSpriteSheetImporter.thumbnails(for: loaded.0)
                    )
                }
            }.value
            guard !isShuttingDown else { return }
            storedImageFiles = restored.manifest
            let referencedNames = Set(restored.manifest.values.flatMap(\.self))
            let decodedNames = Set(restored.files.values.flatMap(\.self))
            imageLoadFailed = referencedNames != decodedNames
            imageLoadError = nil
            if !restored.manifest.isEmpty {
                importedImages = restored.images
                imageThumbnails = restored.thumbnails
            }
            // Sweep only when the decoded set is complete and the mirror agrees with the manifest.
            // Disagreement means another build updated the mirror after this manifest, so the mixed
            // state is uncertain and unknown frames must survive until a deliberate save.
            if !imageLoadFailed, legacyFiles == restored.manifest {
                await reconcileSavedPetImages(storage)
            }
        } catch {
            imageLoadFailed = true
            imageLoadError = error
            storedImageFiles = legacyFiles
            await showImageSaveError(error)
        }
    }

    /// Sweep files the committed manifest no longer references. Best effort: a failure retries on
    /// the next launch without blocking the images that are already displayed.
    private func reconcileSavedPetImages(_ storage: PetImageStorage) async {
        await Task.detached(priority: .utility) {
            _ = try? storage.reconcileFiles()
        }.value
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
        imageLoadError = nil
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
        imageLoadError = nil
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

/// The manifest, decoded images, their frame names, and thumbnails restored from disk in one pass.
private struct RestoredPetImages {
    let manifest: [String: [String]]
    let images: PetImageSet
    let files: [String: [String]]
    let thumbnails: [ObjectIdentifier: NSImage]
}

/// Read the committed manifest, or migrate the legacy defaults to disk when it is missing.
///
/// Migration writes the mirror first so the reconciliation that follows can never delete a frame
/// the legacy state still referenced. With no manifest and no legacy mirror, nothing is committed:
/// the returned empty manifest only means "show nothing", while the reconciling sweep sees `nil`
/// and leaves the on-disk frames of uncertain provenance untouched. An explicitly committed empty
/// manifest is different and stays authoritative.
private func committedOrMigratedManifest(
    _ storage: PetImageStorage,
    legacy: [String: [String]]
) throws -> [String: [String]] {
    if let committed = try storage.readManifest() {
        return committed
    }
    guard !legacy.isEmpty else { return [:] }
    try storage.commitManifest(legacy)
    return legacy
}
