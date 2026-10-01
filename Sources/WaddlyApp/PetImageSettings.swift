import AppKit
import WaddlyCore

extension AppDelegate {
    func loadSavedPetImage() {
        let legacyImages = customPetImageURL.flatMap { url -> PetImageSet? in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  size.intValue <= PetSpriteSheetImporter.maximumFileSize,
                  let data = try? Data(contentsOf: url) else { return nil }
            return PetSpriteSheetImporter.frames(from: data)
        }
        var loadedImages = legacyImages ?? PetImageSet()
        guard let directory = petImagesDirectoryURL else {
            importedImages = legacyImages
            return
        }

        let manifest = defaults.dictionary(forKey: "petImageFiles") as? [String: [String]] ?? [:]
        for category in PetImageCategory.allCases {
            let names = manifest[category.rawValue] ?? []
            var validNames: [String] = []
            let savedImages = names.compactMap { name -> NSImage? in
                guard name.hasSuffix(".png"), UUID(uuidString: String(name.dropLast(4))) != nil else {
                    return nil
                }
                guard let image = PetSpriteSheetImporter.load(
                    from: directory.appendingPathComponent(name)
                ) else { return nil }
                validNames.append(name)
                return image
            }
            if !savedImages.isEmpty { loadedImages[category] = savedImages }
            storedImageFiles[category.rawValue] = validNames
        }
        if legacyImages != nil || !manifest.isEmpty { importedImages = loadedImages }
    }

    func importPetImage(from url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= PetSpriteSheetImporter.maximumFileSize,
              let data = try? Data(contentsOf: url),
              let newImages = PetSpriteSheetImporter.frames(from: data) else {
            showPetImageImportError()
            return false
        }
        guard confirmPetImageImport(data, cellSize: Int(newImages[.idle][0].size.width)) else { return false }

        do {
            try persistPetImages(newImages)
        } catch {
            showImageSaveError()
            return false
        }

        importedImages = newImages
        imageSetDidChange(resetActivity: true)
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
        showAlert("pet.importErrorTitle", "pet.importErrorMessage")
    }

    func showImageSaveError() {
        showAlert("images.saveErrorTitle", "images.saveErrorMessage")
    }

    func showAlert(_ titleKey: String, _ messageKey: String) {
        let alert = NSAlert()
        alert.messageText = localizedString(titleKey)
        alert.informativeText = localizedString(messageKey)
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func confirmPetImageImport(_ data: Data, cellSize: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = localizedString("pet.previewTitle")
        alert.informativeText = localizedString("pet.previewPrompt")
        alert.alertStyle = .informational

        let previewSize: CGFloat = 240
        let detailsHeight: CGFloat = 72
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: previewSize, height: previewSize + detailsHeight))
        let imageView = NSImageView(frame: NSRect(x: 0, y: detailsHeight, width: previewSize, height: previewSize))
        imageView.image = NSImage(data: data)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.layer?.borderWidth = 1
        imageView.setAccessibilityLabel(localizedString("a11y.spritePreview"))

        let grid = SpriteSheetGridOverlay(frame: imageView.bounds)
        grid.autoresizingMask = [.width, .height]
        imageView.addSubview(grid)
        accessory.addSubview(imageView)

        let imageSize = cellSize * 3
        let details = [
            "\(localizedString("pet.previewImageSize")) \(imageSize) × \(imageSize) px",
            "\(localizedString("pet.previewCellSize")) \(cellSize) × \(cellSize) px",
            "\(localizedString("pet.previewDisplaySize")) \(Int(displaySize)) px",
            localizedString("pet.previewPosition")
        ].joined(separator: "\n")
        let detailsLabel = NSTextField(wrappingLabelWithString: details)
        detailsLabel.frame = NSRect(x: 0, y: 0, width: previewSize, height: detailsHeight)
        accessory.addSubview(detailsLabel)

        alert.accessoryView = accessory
        alert.addButton(withTitle: localizedString("pet.importConfirm"))
        alert.addButton(withTitle: localizedString("common.cancel"))
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
            window.title = localizedString("images.windowTitle")
            window.minSize = NSSize(width: 620, height: 670)
            window.isReleasedWhenClosed = false

            let content = NSView()
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(stack)

            let note = NSTextField(wrappingLabelWithString: localizedString("images.instructions"))
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
        picker.prompt = localizedString("images.add")
        guard picker.runModal() == .OK else { return }
        addImages(picker.urls, to: category)
    }

}
