import AppKit

/// Shared window metrics keep the hosted preview and SwiftUI layout aligned.
enum SetupMetrics {
    static let contentSize = NSSize(width: 820, height: 520)
    /// The guide parks beside System Settings, where the app list has to stay visible, so it gives up
    /// the preview column and the width that column needed. 480 keeps the window left of the list on
    /// a 1200 pt-wide display: the settings window starts near 290 pt and its sidebar is 230 pt wide.
    /// 540 is the tallest content height whose titled frame still parks inside a 602 pt-tall display.
    static let compactGuideSize = NSSize(width: 480, height: 540)
    static let previewCornerRadius: CGFloat = 16
}

extension SetupWizardController {
    func localizedString(_ key: LocalizationKey) -> String {
        localization.string(for: key)
    }

    func refreshLocalization() {
        window?.title = localizedString(isMonitoringSettings ? .setupSetUpMonitoring : .setupWindowTitle)
        renderCurrentStep()
    }
}
