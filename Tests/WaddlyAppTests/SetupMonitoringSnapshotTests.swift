import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Captures for the Keyboard reactions step, which is also the Input Monitoring settings screen.
/// Opt-in via `WADDLY_CAPTURE_CHARACTER_IMPORT=1`; with the variable unset the suite does nothing.
///
/// The four states are captured in one place because the layout is shared: the page header, the
/// instruction card, and the actions must read the same whether the permission is missing, guiding,
/// manual, or waiting for a first key.
@Suite(.serialized) @MainActor struct SetupMonitoringSnapshotTests {
    @Test func capturesMonitoringStepSurfaces() async throws {
        guard CaptureHarness.isEnabled else { return }
        try CaptureHarness.prepare()
        for language in [AppLanguage.english, .japanese] {
            for dark in [false, true] {
                try await captureMonitoring(language: language, dark: dark)
            }
        }
    }
}

@MainActor
private extension SetupMonitoringSnapshotTests {
    func captureMonitoring(language: AppLanguage, dark: Bool) async throws {
        let tag = CaptureHarness.suffix(language, dark)
        let missing = try makeWizard(language: language, granted: false)
        defer { missing.close() }
        let content = try #require(missing.window?.contentView)

        try await capture(content, dark: dark, named: "monitoring-off-\(tag)")
        missing.enableMonitoring()
        try await capture(content, dark: dark, named: "monitoring-guide-\(tag)")
        missing.toggleManualSteps()
        try await capture(content, dark: dark, named: "monitoring-manual-\(tag)")

        let waiting = try makeWizard(language: language, granted: true, observedReaction: false)
        defer { waiting.close() }
        try await capture(
            #require(waiting.window?.contentView),
            dark: dark,
            named: "monitoring-waiting-\(tag)"
        )

        // The same page inside onboarding, where the progress header and the three footer actions
        // have to fit the narrow guide too.
        let onboarding = try makeWizard(language: language, granted: false, isMonitoringSettings: false)
        defer { onboarding.close() }
        onboarding.enableMonitoring()
        try await capture(
            #require(onboarding.window?.contentView),
            dark: dark,
            named: "monitoring-guide-onboarding-\(tag)"
        )
    }

    /// The preview player publishes its first frame off the main run loop, and a step change can
    /// resize the window, so let both land before rendering.
    func capture(_ content: NSView, dark: Bool, named name: String) async throws {
        try await Task.sleep(for: .milliseconds(250))
        try CaptureHarness.write(content, dark: dark, named: name)
    }

    /// The menu entry reopens this screen after setup, so the captures default to that presentation.
    func makeWizard(
        language: AppLanguage,
        granted: Bool,
        observedReaction: Bool = false,
        isMonitoringSettings: Bool = true
    ) throws -> SetupWizardController {
        let state = SetupWizardFixture.State()
        state.images = try SetupWizardFixture.sheetImages()
        return try SetupWizardFixture.makeWizard(
            language: language,
            state: state,
            savedStep: SetupWizardController.Step.monitoring.rawValue,
            granted: granted,
            observedReaction: observedReaction,
            requestPermission: { false },
            isMonitoringSettings: isMonitoringSettings
        )
    }
}
