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

    /// Commits the decoded set; the wizard does not present a separate confirmation step. The
    /// store's serialized queue owns persistence; the refusal rule runs inside that queue so a
    /// sample requested by a reopened window cannot land after a user import already wrote one.
    func confirmPetImage(_ images: PetImageSet, source: PetImageCommitSource = .userFile) async -> Bool {
        await queueImageUpdate { await self.confirmPetImageInOrder(images, source: source) }
    }

    /// A user's own file always wins: a sample commit is refused once any pet is stored. Pure so the
    /// rule is testable without a queue.
    nonisolated static func shouldCommitPetImages(source: PetImageCommitSource, petIsStored: Bool) -> Bool {
        source == .userFile || !petIsStored
    }

    private func confirmPetImageInOrder(_ images: PetImageSet, source: PetImageCommitSource) async -> Bool {
        guard Self.shouldCommitPetImages(source: source, petIsStored: hasCompletePetImageSet) else {
            return false
        }
        do {
            try await persistPetImages(images, resetActivity: true)
        } catch {
            await showImageSaveError(error)
            return false
        }
        return true
    }

    func imageSetDidChange(resetActivity: Bool = false) {
        guard hasCompletePetImageSet else {
            presenter.hide(panel)
            animationController.imageSetDidChange(resetActivity: resetActivity)
            return
        }
        presenter.reveal(panel)
        animationController.imageSetDidChange(resetActivity: resetActivity)
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
        let candidates = [characterImportWindowController?.window, setupWizardController?.window]
            .compactMap(\.self)
        if let keyWindow = candidates.first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let visibleWindow = candidates.first(where: \.isVisible) {
            return visibleWindow
        }
        guard hasCompletePetImageSet else {
            showSetupWizard()
            return setupWizardController?.window
        }
        return panel
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
}
