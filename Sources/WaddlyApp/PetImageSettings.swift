import AppKit
import WaddlyCore

extension AppDelegate {
    func loadSavedPetImage() async {
        guard let directory = petImagesDirectoryURL else { return }
        let manifest = settings.petImageFiles
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try autoreleasepool { try PetImageStorage(directory: directory).load(manifest) }
            }.value
            guard !isShuttingDown else { return }
            storedImageFiles = loaded.1
            if !manifest.isEmpty {
                importedImages = loaded.0
            }
        } catch {
            imageLoadFailed = true
            storedImageFiles = manifest
            showImageSaveError(error)
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
            showPetImageImportError()
            return false
        }
        guard confirmPetImageImport(preview, cellSize: Int(newImages[.idle][0].size.width)) else { return false }
        do {
            try await persistPetImages(newImages, resetActivity: true)
        } catch {
            showImageSaveError(error)
            return false
        }
        imageLoadFailed = false
        return true
    }

    func imageSetDidChange(resetActivity: Bool = false) {
        for category in PetImageCategory.allCases {
            imageRows[category]?.setImages(petImages[category])
        }
        guard hasCompletePetImageSet else {
            panel.orderOut(nil)
            animationController.imageSetDidChange(resetActivity: resetActivity)
            return
        }
        panel.orderFrontRegardless()
        animationController.imageSetDidChange(resetActivity: resetActivity)
    }

    private func showPetImageImportError() {
        showAlert(.petImportErrorTitle, .petImportErrorMessage)
    }

    func showImageSaveError(_ error: Error) {
        guard !isShuttingDown else { return }
        if error is PetImageStorageError {
            showAlert(.imagesErrorTitle, .imagesMemoryLimit)
        } else {
            showAlert(.imagesSaveErrorTitle, .imagesSaveErrorMessage)
        }
    }

    func showAlert(_ titleKey: LocalizationKey, _ messageKey: LocalizationKey) {
        let alert = NSAlert()
        alert.messageText = localizedString(titleKey)
        alert.informativeText = localizedString(messageKey)
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func confirmPetImageImport(_ preview: NSImage, cellSize: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = localizedString(.petPreviewTitle)
        alert.informativeText = localizedString(.petPreviewPrompt)
        alert.alertStyle = .informational

        let previewSize: CGFloat = 240
        let detailsHeight: CGFloat = 72
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: previewSize, height: previewSize + detailsHeight))
        let imageView = NSImageView(frame: NSRect(x: 0, y: detailsHeight, width: previewSize, height: previewSize))
        imageView.image = preview
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.layer?.borderWidth = 1
        imageView.setAccessibilityLabel(localizedString(.a11ySpritePreview))

        let grid = SpriteSheetGridOverlay(frame: imageView.bounds)
        grid.autoresizingMask = [.width, .height]
        imageView.addSubview(grid)
        accessory.addSubview(imageView)

        let imageSize = cellSize * 3
        let details = [
            "\(localizedString(.petPreviewImageSize)) \(imageSize) × \(imageSize) px",
            "\(localizedString(.petPreviewCellSize)) \(cellSize) × \(cellSize) px",
            "\(localizedString(.petPreviewDisplaySize)) \(Int(displaySize)) px",
            localizedString(.petPreviewPosition)
        ].joined(separator: "\n")
        let detailsLabel = NSTextField(wrappingLabelWithString: details)
        detailsLabel.frame = NSRect(x: 0, y: 0, width: previewSize, height: detailsHeight)
        accessory.addSubview(detailsLabel)

        alert.accessoryView = accessory
        alert.addButton(withTitle: localizedString(.petImportConfirm))
        alert.addButton(withTitle: localizedString(.commonCancel))
        return alert.runModal() == .alertFirstButtonReturn
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
                let row = PetImageCategoryRowView(category: category, images: petImages[category])
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
            window.contentView = content
            imageSettingsWindow = window
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        imageSettingsWindow?.makeKeyAndOrderFront(nil)
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
