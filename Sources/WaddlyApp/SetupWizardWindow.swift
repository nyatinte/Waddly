import AppKit
import SwiftUI

extension SetupWizardController {
    func buildWindow() {
        let contentView = PetImageDropView()
        contentView.idleBorderWidth = 0
        contentView.shouldPreserveUnsupportedDropURLs = { [weak self] in self?.isComposingCharacter ?? false }
        contentView.onDrop = { [weak self] urls in
            self?.handleWindowDrop(urls)
        }

        previewPane.configure(localization: localization, showsControls: true)
        previewPane.shouldPreserveUnsupportedDropURLs = { [weak self] in self?.isComposingCharacter ?? false }
        previewPane.onDrop = { [weak self] urls in
            self?.handleWindowDrop(urls)
        }

        let hostingView = NSHostingView(rootView: SetupWizardScreen(controller: self))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        bindPermission()
        window?.contentView = contentView
        renderCurrentStep()
    }

    /// All step changes funnel through here so the saved step always matches the screen.
    func setStep(_ step: Step?) {
        currentStep = step ?? .pet
        // The inline import error belongs to the step where the drop happened, not the next one.
        clearImportFeedback()
        onStepChange(step?.rawValue)
        renderCurrentStep()
    }
}
