import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp
import WaddlyCore

typealias Fixture = SetupWizardFixture

@Suite(.serialized) @MainActor struct SetupWizardTests {
    @Test(arguments: [AppLanguage.japanese, .english])
    func hostsSwiftUIAndKeepsItsDesignedWindowSize(language: AppLanguage) throws {
        let wizard = try Fixture.makeWizard(language: language, demoURL: Fixture.sheetURL())
        defer { wizard.close() }
        let window = try #require(wizard.window)
        #expect(window.contentView?.subviews.contains { $0 is NSHostingView<SetupWizardScreen> } == true)
        #expect(window.contentView?.bounds.size == SetupMetrics.contentSize)
        #expect(wizard.previewPane.hasPet)
        #expect(!wizard.hasImage)
    }

    @Test func stepChangesPersistAndFinishHandsThePetToTheDesktop() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        var recorded: [Int?] = []
        var revealed = false
        let wizard = try Fixture.makeWizard(
            state: state,
            onStepChange: { recorded.append($0) },
            onShowOnDesktop: { revealed = true }
        )
        defer { wizard.close() }

        wizard.goNext()
        #expect(wizard.currentStep == .monitoring)
        #expect(recorded.last == SetupWizardController.Step.monitoring.rawValue)
        wizard.deferMonitoring()
        #expect(wizard.currentStep == .completed)
        #expect(!wizard.isMonitoringReady)
        wizard.goNext()
        #expect(recorded.last == .some(nil))
        #expect(revealed)
        #expect(state.closed)
    }

    @Test func setupCannotAdvanceWithoutAnImage() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        wizard.goNext()
        #expect(wizard.currentStep == .pet)
        #expect(!wizard.hasImage)
    }

    @Test func permissionActionEntersTheGuideAndManualFallback() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(state: state, requestPermission: { false })
        defer { wizard.close() }
        wizard.goNext()
        wizard.enableMonitoring()
        #expect(wizard.isShowingGuide)
        #expect(wizard.previewPane.isShowingGuide)
        wizard.toggleManualSteps()
        #expect(wizard.isShowingManualSteps)
        #expect(wizard.isShowingGuide)
        wizard.toggleManualSteps()
        #expect(!wizard.isShowingManualSteps)
    }

    @Test func importUpdatesTheSwiftUIObservedStateWithoutChangingTheStep() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(
            state: state,
            previewResult: Fixture.sheetImages(),
            confirmResult: true
        )
        defer { wizard.close() }
        let sheetURL = try Fixture.sheetURL()
        wizard.importImage(from: sheetURL)
        try await Fixture.waitUntil { wizard.hasImage }
        #expect(wizard.currentStep == .pet)
        #expect(wizard.didRegisterPet)
        #expect(wizard.importedFileName == sheetURL.lastPathComponent)
        #expect(wizard.previewPane.hasPet)
    }

    @Test func closingStopsPreviewAndReopeningCanResumeIt() throws {
        let wizard = try Fixture.makeWizard(demoURL: Fixture.sheetURL())
        defer { wizard.close() }
        #expect(wizard.previewPane.isPlayingPreview)
        wizard.previewPane.stopPlayback()
        #expect(!wizard.previewPane.isPlayingPreview)
        wizard.renderCurrentStep()
        #expect(wizard.previewPane.isPlayingPreview)
    }
}
