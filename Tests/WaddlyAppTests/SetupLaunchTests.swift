import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Launch-time setup decisions: an unfinished step is the resume signal, so the restart macOS asks
/// for after an Input Monitoring grant comes back to the same page instead of leaving setup half-done.
@Suite(.serialized) @MainActor struct SetupLaunchTests {
    @Test(arguments: LaunchCase.all)
    func launchReopensSetupUntilItIsFinished(scenario: LaunchCase) async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        if scenario.hasImages {
            try await app.persistPetImages(fixture.exampleImages())
        }
        app.settings.setupWizardSeen = scenario.seen
        app.settings.setupStep = scenario.step

        #expect(app.shouldOpenSetupOnLaunch == scenario.expectsSetupOnLaunch, "\(scenario.name)")
        #expect(app.isSetupComplete == scenario.isComplete, "\(scenario.name)")
    }

    /// Terminating for the restart macOS asks for closes the window, and closing marks the guide
    /// seen. The unfinished step must still bring the guide back on the next launch, at the same page.
    @Test func restartingMidSetupReopensTheSavedStep() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.settings.setupWizardSeen = false
        app.settings.setupStep = nil
        app.showSetupWizard()
        let wizard = try #require(app.setupWizardController)
        wizard.goNext()
        #expect(app.settings.setupStep == SetupWizardController.Step.monitoring.rawValue)

        // Closing is what termination does to the window before the process exits.
        wizard.close()
        #expect(app.settings.setupWizardSeen)
        #expect(app.shouldOpenSetupOnLaunch)

        app.showSetupWizard()
        #expect(app.setupWizardController?.currentStep == .monitoring)
    }
}

/// The launch cases, named so a failure says which state broke.
struct LaunchCase: Sendable {
    let name: String
    let hasImages: Bool
    let seen: Bool
    let step: Int?
    let expectsSetupOnLaunch: Bool
    let isComplete: Bool

    static let all: [LaunchCase] = [
        LaunchCase(
            name: "nothing yet",
            hasImages: false,
            seen: false,
            step: nil,
            expectsSetupOnLaunch: true,
            isComplete: false
        ),
        LaunchCase(
            name: "no images",
            hasImages: false,
            seen: true,
            step: nil,
            expectsSetupOnLaunch: true,
            isComplete: false
        ),
        LaunchCase(
            name: "images, never finished",
            hasImages: true,
            seen: false,
            step: nil,
            expectsSetupOnLaunch: true,
            isComplete: false
        ),
        LaunchCase(
            name: "images, unfinished monitoring step",
            hasImages: true,
            seen: true,
            step: SetupWizardController.Step.monitoring.rawValue,
            expectsSetupOnLaunch: true,
            isComplete: false
        ),
        LaunchCase(
            name: "images, unfinished completion page",
            hasImages: true,
            seen: true,
            step: SetupWizardController.Step.completed.rawValue,
            expectsSetupOnLaunch: true,
            isComplete: false
        ),
        LaunchCase(
            name: "finished",
            hasImages: true,
            seen: true,
            step: nil,
            expectsSetupOnLaunch: false,
            isComplete: true
        )
    ]
}
