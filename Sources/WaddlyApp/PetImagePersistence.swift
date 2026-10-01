import AppKit
import WaddlyCore

extension AppDelegate {
    func persistPetImages(_ imageSet: PetImageSet) throws {
        guard let directory = petImagesDirectoryURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let oldFiles = storedImageFiles
        var newFiles: [String: [String]] = [:]
        var createdURLs: [URL] = []
        do {
            for category in PetImageCategory.allCases {
                let images = imageSet[category]
                guard !images.isEmpty else { throw CocoaError(.validationMissingMandatoryProperty) }
                for image in images {
                    guard let data = PetSpriteSheetImporter.pngData(for: image),
                          data.count <= PetSpriteSheetImporter.maximumFileSize else {
                        throw CocoaError(.fileWriteOutOfSpace)
                    }
                    let name = "\(UUID().uuidString).png"
                    let url = directory.appendingPathComponent(name)
                    try data.write(to: url, options: .atomic)
                    createdURLs.append(url)
                    newFiles[category.rawValue, default: []].append(name)
                }
            }
        } catch {
            createdURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }

        settings.petImageFiles = newFiles
        storedImageFiles = newFiles
        for names in oldFiles.values {
            for name in names where !newFiles.values.contains(where: { $0.contains(name) }) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    func addImages(_ urls: [URL], to category: PetImageCategory) {
        var updated = petImages
        var addedCount = 0
        var skippedCount = 0
        var saveFailed = false
        for url in urls {
            guard url.pathExtension.lowercased() == "png",
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  size.intValue <= PetSpriteSheetImporter.maximumFileSize,
                  let data = try? Data(contentsOf: url),
                  let optimized = PetSpriteSheetImporter.optimizedImage(from: data) else {
                skippedCount += 1
                continue
            }
            do {
                try persistAddedImage(
                    optimized.image,
                    data: optimized.pngData,
                    existingImages: updated[category],
                    to: category
                )
                updated[category].append(optimized.image)
                importedImages = updated
                addedCount += 1
            } catch {
                saveFailed = true
                break
            }
        }
        guard addedCount > 0 else {
            showAlert("images.errorTitle", "images.errorMessage")
            return
        }
        imageSetDidChange()
        if saveFailed {
            showImageSaveError()
        } else if skippedCount > 0 {
            showAlert("images.skippedTitle", "images.skippedMessage")
        }
    }

    private func persistAddedImage(
        _ image: NSImage,
        data: Data,
        existingImages: [NSImage],
        to category: PetImageCategory
    ) throws {
        guard let directory = petImagesDirectoryURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = category.rawValue
        let previousFiles = storedImageFiles[key] ?? []
        var names = previousFiles
        var createdURLs: [URL] = []
        do {
            if names.count != existingImages.count {
                names = []
                for existingImage in existingImages {
                    guard let imageData = PetSpriteSheetImporter.pngData(for: existingImage),
                          imageData.count <= PetSpriteSheetImporter.maximumFileSize else {
                        throw CocoaError(.fileWriteOutOfSpace)
                    }
                    let name = "\(UUID().uuidString).png"
                    let url = directory.appendingPathComponent(name)
                    try imageData.write(to: url, options: .atomic)
                    createdURLs.append(url)
                    names.append(name)
                }
            }
            let name = "\(UUID().uuidString).png"
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            createdURLs.append(url)
            names.append(name)
        } catch {
            createdURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }

        var updatedFiles = storedImageFiles
        updatedFiles[key] = names
        settings.petImageFiles = updatedFiles
        storedImageFiles = updatedFiles
        for name in previousFiles where !names.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    func removeImage(at index: Int, from category: PetImageCategory) {
        var updated = petImages
        guard updated[category].count > 1, updated[category].indices.contains(index) else { return }
        updated[category].remove(at: index)
        let key = category.rawValue
        let oldNames = storedImageFiles[key] ?? []
        if oldNames.count == petImages[category].count {
            var updatedFiles = storedImageFiles
            var newNames = oldNames
            let removedName = newNames.remove(at: index)
            updatedFiles[key] = newNames
            settings.petImageFiles = updatedFiles
            storedImageFiles = updatedFiles
            if let directory = petImagesDirectoryURL {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(removedName))
            }
        } else {
            do {
                try persistCategoryImages(updated[category], for: category)
            } catch {
                showImageSaveError()
                return
            }
        }
        importedImages = updated
        imageSetDidChange()
    }

    func moveImage(from source: Int, to destination: Int, in category: PetImageCategory) {
        let current = petImages[category]
        guard source != destination, let reordered = moving(current, from: source, to: destination) else { return }
        let key = category.rawValue
        let names = storedImageFiles[key] ?? []
        if names.count == current.count {
            var reorderedNames = names
            let name = reorderedNames.remove(at: source)
            reorderedNames.insert(name, at: destination)
            var updatedFiles = storedImageFiles
            updatedFiles[key] = reorderedNames
            settings.petImageFiles = updatedFiles
            storedImageFiles = updatedFiles
        } else {
            do {
                try persistCategoryImages(reordered, for: category)
            } catch {
                showImageSaveError()
                return
            }
        }
        var updated = petImages
        updated[category] = reordered
        importedImages = updated
        imageSetDidChange()
    }

    private func persistCategoryImages(_ images: [NSImage], for category: PetImageCategory) throws {
        guard !images.isEmpty, let directory = petImagesDirectoryURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var names: [String] = []
        var createdURLs: [URL] = []
        do {
            for image in images {
                guard let data = PetSpriteSheetImporter.pngData(for: image),
                      data.count <= PetSpriteSheetImporter.maximumFileSize else {
                    throw CocoaError(.fileWriteOutOfSpace)
                }
                let name = "\(UUID().uuidString).png"
                let url = directory.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                createdURLs.append(url)
                names.append(name)
            }
        } catch {
            createdURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }

        let oldFiles = storedImageFiles
        var updatedFiles = storedImageFiles
        updatedFiles[category.rawValue] = names
        settings.petImageFiles = updatedFiles
        storedImageFiles = updatedFiles
        for oldNames in oldFiles.values {
            for name in oldNames where !updatedFiles.values.contains(where: { $0.contains(name) }) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

}
