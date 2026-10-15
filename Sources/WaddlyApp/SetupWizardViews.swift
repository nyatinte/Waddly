import AppKit

/// Shared window metrics keep the hosted preview and SwiftUI layout aligned.
enum SetupMetrics {
    static let contentSize = NSSize(width: 820, height: 520)
    static let sideInset: CGFloat = 28
    static let topInset: CGFloat = 22
    static let bottomInset: CGFloat = 20
    static let leftColumnWidth: CGFloat = 410
    static let rightColumnWidth: CGFloat = 330
    static let columnGap: CGFloat = 24
    static let footerHeight: CGFloat = 36
    static let cardCornerRadius: CGFloat = 12
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
