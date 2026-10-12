import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Short alias: the full name pushes several expectations past the line limit.
typealias Fixture = SetupWizardFixture

@Suite(.serialized) @MainActor struct SetupWizardTests {
    @Test func welcomeStepOffersImportTargetsWithHandlers() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        let panes = Fixture.descendants(of: content).compactMap { $0 as? SetupPreviewPane }
        #expect(!panes.isEmpty)
        let targets = Fixture.descendants(of: content).compactMap { $0 as? PetImageDropView }
            .filter { $0.registeredDraggedTypes.contains(.fileURL) }
        #expect(!targets.isEmpty)
        for target in targets {
            #expect(target.onDrop != nil)
        }
    }

    @Test(arguments: [AppLanguage.japanese, .english])
    func everyStepKeepsItsTextInsideTheWindow(language: AppLanguage) throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(language: language, state: state, demoURL: Fixture.sheetURL())
        defer { wizard.close() }
        let window = try #require(wizard.window)
        let content = try #require(window.contentView)
        for step in SetupWizardController.Step.allCases {
            wizard.currentStep = step
            wizard.renderCurrentStep()
            window.setContentSize(SetupMetrics.contentSize)
            window.layoutIfNeeded()
            // The window must not grow between states.
            #expect(window.contentView?.bounds.height == SetupMetrics.contentSize.height)
            #expect(window.contentView?.bounds.width == SetupMetrics.contentSize.width)
            content.layoutSubtreeIfNeeded()
            for label in Fixture.descendants(of: content).compactMap({ $0 as? NSTextField }) {
                let frame = label.convert(label.bounds, to: content)
                #expect(frame.minY >= -1, "\(step): \(label.stringValue)")
                #expect(frame.maxY <= content.bounds.maxY + 1, "\(step): \(label.stringValue)")
                #expect(frame.minX >= -1, "\(step): \(label.stringValue)")
                #expect(frame.maxX <= content.bounds.maxX + 1, "\(step): \(label.stringValue)")
            }
        }
        _ = try Fixture.button("goNext", in: content)
    }

    @Test(arguments: [AppLanguage.japanese, .english])
    func windowSizeStaysFixedForEveryState(language: AppLanguage) throws {
        for variant in SetupStateVariant.all {
            let state = Fixture.State()
            state.images = variant.hasImages ? try Fixture.sheetImages() : PetImageSet()
            let wizard = try Fixture.makeWizard(
                language: language,
                state: state,
                demoURL: Fixture.sheetURL(),
                granted: variant.isGranted,
                requestPermission: { variant.isGranted }
            )
            defer { wizard.close() }
            wizard.currentStep = variant.step
            wizard.isShowingChatGPTGuide = variant.isGuide
            wizard.isShowingTroubleshooting = variant.troubleshooting
            if variant.dropGuide {
                // Drive the real state machine instead of poking a flag.
                wizard.permission.beginGuiding()
                if variant.manualSteps {
                    wizard.permission.toggleManualSteps()
                }
            }
            wizard.didRegisterPet = variant.hasImages
            wizard.renderCurrentStep()
            let window = try #require(wizard.window)
            window.layoutIfNeeded()
            let content = try #require(window.contentView)
            // NSWindow grows to its content's fitting size, so a page must never ask for more room.
            #expect(
                content.fittingSize.height <= SetupMetrics.contentSize.height,
                "\(language) \(variant.name) needs \(content.fittingSize.height)pt"
            )
            #expect(
                content.fittingSize.width <= SetupMetrics.contentSize.width,
                "\(language) \(variant.name) needs \(content.fittingSize.width)pt wide"
            )
        }
    }

    @Test func troubleshootingStaysInsideTheWizard() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(state: state, granted: true, requestPermission: { true })
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        try Fixture.button("goNext", in: content).performClick(nil)

        try Fixture.button("toggleTroubleshooting", in: content).performClick(nil)
        #expect(wizard.isShowingTroubleshooting)
        // The regression: this used to hide the wizard and open a floating panel, losing the window.
        #expect(!wizard.isShowingDropGuide)
        let actions = Fixture.descendants(of: content).compactMap { $0 as? NSButton }
            .filter { !$0.isHidden }
            .compactMap(\.action)
            .map(NSStringFromSelector)
        #expect(actions.contains("relaunchApp"))
        #expect(actions.contains("revealInFinder"))
        #expect(actions.contains("openInputMonitoringSettings"))
    }

    @Test func imageRowsKeepTheirScrollViewAsAnInputTarget() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let row = PetImageCategoryRowView(
            category: .typing,
            images: (0 ..< 12).map { _ in NSImage(size: NSSize(width: 2, height: 2)) },
            localization: wizard.localization
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 138),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = row
        row.layoutSubtreeIfNeeded()
        let scroll = try #require(Fixture.descendants(of: row).compactMap { $0 as? NSScrollView }.first)
        let point = scroll.convert(NSPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: row)
        let hit = try #require(row.hitTest(point))
        #expect(hit === scroll || hit.isDescendant(of: scroll))
    }

    @Test func wizardRequiresImagesAndFinishesOnTheDesktopHandoff() throws {
        let state = Fixture.State()
        var revealedOnDesktop = false
        let wizard = try Fixture.makeWizard(
            state: state,
            onShowOnDesktop: { revealedOnDesktop = true }
        )
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)

        #expect(try !Fixture.button("goNext", in: content).isEnabled)
        #expect(Fixture.descendants(of: content).compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == wizard.localizedString(.setupImageMissing) })

        state.images = try Fixture.sheetImages()
        wizard.renderCurrentStep()
        #expect(try Fixture.button("goNext", in: content).isEnabled)

        try Fixture.button("goNext", in: content).performClick(nil)
        #expect(Fixture.descendants(of: content).compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == wizard.localizedString(.setupMonitoringStatusOff) })

        try Fixture.button("goNext", in: content).performClick(nil)
        #expect(try Fixture.button("goNext", in: content).title == wizard.localizedString(.setupShowOnDesktop))

        try Fixture.button("goNext", in: content).performClick(nil)
        #expect(revealedOnDesktop)
        #expect(state.closed)
    }

    @Test func chatGPTGuideOpensInlineAndReturnsToTheMethodChoices() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)

        #expect(Fixture.descendants(of: content).compactMap { $0 as? SetupOptionCard }.count == 2)
        try Fixture.optionCard("showChatGPTGuide", in: content).activate()
        #expect(Fixture.descendants(of: content).compactMap { $0 as? SetupOptionCard }.isEmpty)
        #expect(Fixture.descendants(of: content).compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == wizard.localizedString(.setupChatGPTPromptTitle) })
        try Fixture.button("changeMethod", in: content).performClick(nil)
        #expect(Fixture.descendants(of: content).compactMap { $0 as? SetupOptionCard }.count == 2)
    }

    @Test func completionScreenReportsMonitoringWithoutClaimingSuccess() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(state: state)
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        try Fixture.button("goNext", in: content).performClick(nil)
        try Fixture.button("deferMonitoring", in: content).performClick(nil)
        let labels = Fixture.descendants(of: content).compactMap { $0 as? NSTextField }.map(\.stringValue)
        #expect(labels.contains(wizard.localizedString(.setupCheckPet)))
        #expect(labels.contains(wizard.localizedString(.setupCheckMonitoringOff)))
        #expect(!labels.contains(wizard.localizedString(.setupCheckMonitoring)))
        #expect(try Fixture.button("goNext", in: content).title == wizard.localizedString(.setupShowOnDesktop))
    }

    @Test func resumesTheSavedStepAfterARestart() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(state: state, savedStep: SetupWizardController.Step.monitoring.rawValue)
        defer { wizard.close() }
        #expect(wizard.currentStep == .monitoring)
        let content = try #require(wizard.window?.contentView)
        #expect(Fixture.descendants(of: content).compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == wizard.localizedString(.setupMonitoringStatusOff) })
    }

    @Test func recordsEveryStepChangeAndClearsItOnFinish() throws {
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
        let content = try #require(wizard.window?.contentView)

        try Fixture.button("goNext", in: content).performClick(nil)
        #expect(recorded.last == SetupWizardController.Step.monitoring.rawValue)
        try Fixture.button("goNext", in: content).performClick(nil)
        #expect(recorded.last == SetupWizardController.Step.completed.rawValue)
        try Fixture.button("goNext", in: content).performClick(nil)
        // Finishing clears the saved step so the next launch is normal use, not setup again.
        #expect(recorded.last == .some(nil))
        #expect(revealed)
    }

    @Test func enablingMonitoringTurnsTheWizardIntoTheDragGuide() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(state: state, requestPermission: { false })
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        try Fixture.button("goNext", in: content).performClick(nil)

        // The guide lives inside the wizard, so the window never disappears or hands off.
        #expect(!wizard.isShowingDropGuide)
        #expect(!Fixture.descendants(of: content).contains { $0 is DraggableAppIconView })
        try Fixture.button("enableMonitoring", in: content).performClick(nil)
        #expect(wizard.isShowingDropGuide)
        #expect(Fixture.descendants(of: content).contains { $0 is DraggableAppIconView })
        let pane = try #require(Fixture.descendants(of: content).compactMap { $0 as? SetupPreviewPane }.first)
        #expect(pane.isShowingGuide)
    }

    @Test func monitoringStepKeepsNextOutOfThePrimaryFlowUntilGranted() throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(state: state, requestPermission: { false })
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        try Fixture.button("goNext", in: content).performClick(nil)

        #expect(try Fixture.button("goNext", in: content).isHidden)
        #expect(try !Fixture.button("deferMonitoring", in: content).isHidden)
        #expect(Fixture.descendants(of: content).compactMap { $0 as? NSButton }
            .contains { $0.action == NSSelectorFromString("enableMonitoring") && !$0.isHidden })
    }

    @Test func previewLoopsEveryCategoryOfTheImportedSheet() throws {
        let shots = try PetPreviewPlayer.demoShots(for: Fixture.sheetImages())
        let count = shots.count
        #expect(count == 9)
        #expect(shots.allSatisfy { $0.seconds > 0 })
    }
}

private struct SetupStateVariant {
    let name: String
    let hasImages: Bool
    let isGranted: Bool
    let step: SetupWizardController.Step
    let isGuide: Bool
    var troubleshooting = false
    var dropGuide = false
    var manualSteps = false

    static let all: [SetupStateVariant] = [
        make("pet-options"),
        make("pet-guide", images: false, guide: true),
        make("pet-registered", images: true),
        make("monitoring-off", images: true, step: .monitoring),
        make("monitoring-on", images: true, step: .monitoring, granted: true),
        make("monitoring-troubleshooting", images: true, step: .monitoring, granted: true, troubleshooting: true),
        make("monitoring-drop-guide", images: true, step: .monitoring, dropGuide: true),
        make("monitoring-drop-guide-manual", images: true, step: .monitoring, dropGuide: true, manualSteps: true),
        make("completed-off", images: true, step: .completed),
        make("completed-on", images: true, step: .completed, granted: true)
    ]

    private static func make(
        _ name: String,
        images: Bool = false,
        step: SetupWizardController.Step = .pet,
        granted: Bool = false,
        guide: Bool = false,
        troubleshooting: Bool = false,
        dropGuide: Bool = false,
        manualSteps: Bool = false
    ) -> SetupStateVariant {
        SetupStateVariant(
            name: name,
            hasImages: images,
            isGranted: granted,
            step: step,
            isGuide: guide,
            troubleshooting: troubleshooting,
            dropGuide: dropGuide,
            manualSteps: manualSteps
        )
    }
}
