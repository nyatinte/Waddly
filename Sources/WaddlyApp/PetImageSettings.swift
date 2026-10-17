import AppKit
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

    /// Commits the decoded set; the wizard does not present a separate confirmation step.
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
        for category in PetImageCategory.allCases {
            imageRows[category]?.setImages(thumbnails(for: category))
        }
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
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = localizedString(.imagesWindowTitle)
            window.minSize = NSSize(width: 620, height: 670)
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
        imageRows.removeAll()
        window.contentView = makeImageSettingsContent()
    }

    private func makeImageSettingsContent() -> NSView {
        let content = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        let note = NSTextField(wrappingLabelWithString: localizedString(.imagesInstructions))
        note.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        for category in PetImageCategory.allCases {
            let row = PetImageCategoryRowView(
                category: category,
                images: thumbnails(for: category),
                localization: localization
            )
            row.onAdd = { [weak self] in self?.chooseImages(for: category) }
            row.onDrop = { [weak self] in self?.addImages($0, to: category) }
            row.onRemove = { [weak self] in self?.removeImage(at: $0, from: category) }
            row.onMove = { [weak self] in self?.moveImage(from: $0, to: $1, in: category) }
            imageRows[category] = row
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
        return content
    }

    func closeImageSettingsWindow() {
        imageSettingsWindow?.contentView = nil
        imageSettingsWindow?.delegate = nil
        imageSettingsWindow = nil
        imageRows.removeAll()
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
