import AppKit

/// Shared window metrics keep the hosted preview and SwiftUI layout aligned.
enum SetupMetrics {
    static let contentSize = NSSize(width: 820, height: 520)
    /// Narrow enough to sit beside System Settings without obscuring its app list.
    static let compactGuideSize = NSSize(width: 420, height: 500)
    static let permissionGuideSize = NSSize(width: 380, height: 400)
    static let permissionGuideMinimumSize = NSSize(width: 380, height: 240)
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
