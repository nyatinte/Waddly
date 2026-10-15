import AppKit
import SwiftUI

extension SetupWizardController {
    func buildWindow() {
        let contentView = PetImageDropView()
        contentView.idleBorderWidth = 0
        contentView.onDrop = { [weak self] urls in
            guard let url = urls.first else { return }
            self?.importImage(from: url)
        }

        previewPane.configure(localization: localization, showsControls: true)
        previewPane.onDrop = { [weak self] urls in
            guard let url = urls.first else { return }
            self?.importImage(from: url)
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
        onStepChange(step?.rawValue)
        renderCurrentStep()
    }
}
