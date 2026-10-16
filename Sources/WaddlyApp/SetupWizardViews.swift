import AppKit

/// Shared window metrics keep the hosted preview and SwiftUI layout aligned.
enum SetupMetrics {
    static let contentSize = NSSize(width: 820, height: 520)
    static let footerHeight: CGFloat = 36
    static let previewCornerRadius: CGFloat = 16
    static let optionCardHeight: CGFloat = 72
}

extension SetupWizardController {
    func localizedString(_ key: LocalizationKey) -> String {
        localization.string(for: key)
    }

    func refreshLocalization() {
        window?.title = localizedString(.setupWindowTitle)
        renderCurrentStep()
    }
}
