import AppKit

/// Shared window metrics keep the hosted preview and SwiftUI layout aligned.
enum SetupMetrics {
    static let contentSize = NSSize(width: 820, height: 520)
    /// The guide parks beside System Settings, where the app list has to stay visible, so it gives up
    /// the preview column and the width that column needed. 480 keeps the window left of the list on
    /// a 1200 pt-wide display: the settings window starts near 290 pt and its sidebar is 230 pt wide.
    static let compactGuideSize = NSSize(width: 480, height: 460)
    static let previewCornerRadius: CGFloat = 16
    static let optionCardHeight: CGFloat = 72
}

extension SetupWizardController {
    func localizedString(_ key: LocalizationKey) -> String {
        localization.string(for: key)
    }

    /// The inline message for the copy/open action, or `nil` before the first attempt.
    var promptFeedbackKey: LocalizationKey? {
        switch promptFeedback {
        case .copied: .setupPromptCopied
        case .copyFailed: .setupCopyFailed
        case .openFailed: .setupOpenFailed
        case nil: nil
        }
    }

    /// Copy and open failures share the warning styling; a successful copy stays secondary.
    var promptFeedbackIsError: Bool {
        promptFeedback == .copyFailed || promptFeedback == .openFailed
    }

    func refreshLocalization() {
        window?.title = localizedString(isMonitoringSettings ? .setupSetUpMonitoring : .setupWindowTitle)
        renderCurrentStep()
    }
}
