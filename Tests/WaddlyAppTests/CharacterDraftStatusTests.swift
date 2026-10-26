import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp
import WaddlyCore

/// The two states the shared character screen can show once it has a complete frame set — the saved
/// pet and an unsaved draft — and the footer action each host allows in those states.
@Suite(.serialized) @MainActor struct CharacterDraftStatusTests {
    @Test func aSavedPetIsCurrentInUseAndOnlyChangeCharacterDisablesApply() throws {
        let saved = try SetupWizardFixture.sheetImages()
        let model = makeModel(current: saved)
        model.reload()

        let window = try makeView(model: model, requiresChange: true)
        let setup = try makeView(model: model, requiresChange: false)

        #expect(window.draftStatus == .currentInUse)
        #expect(!window.isPrimaryActionEnabled)
        // Setup's Continue still has to commit a valid, unchanged pet so the step can advance.
        #expect(setup.draftStatus == .currentInUse)
        #expect(setup.isPrimaryActionEnabled)
    }

    @Test func anUnchangedSetupPetStillCommitsAndAdvances() async throws {
        let state = Fixture.State()
        state.images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(state: state)
        defer { wizard.close() }
        wizard.beginCharacterImport()
        let model = wizard.characterImportModel
        #expect(model.stagedFrames?.isComplete == true)
        #expect(!model.hasUnsavedChanges)

        await wizard.commitCharacterImportAndContinue().value

        #expect(state.commitCharacterCount == 1)
        #expect(!wizard.isComposingCharacter)
        #expect(wizard.currentStep == .monitoring)
    }

    @Test func anImportedDraftIsNotSavedAndApplicable() async throws {
        let model = try makeModel(current: SetupWizardFixture.sheetImages())
        model.reload()
        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])

        let view = try makeView(model: model, requiresChange: true)
        #expect(view.draftStatus == .notSaved)
        #expect(view.isPrimaryActionEnabled)
    }

    @Test func aFrameEditedDraftIsNotSavedAndApplicable() throws {
        let model = try makeModel(current: SetupWizardFixture.sheetImages())
        model.reload()
        var edited = try #require(model.stagedFrames)
        edited[.idle][0] = try #require(edited[.typing].first)
        model.stageFrameEdited(edited)

        let view = try makeView(model: model, requiresChange: true)
        #expect(view.draftStatus == .notSaved)
        #expect(view.isPrimaryActionEnabled)
    }

    @Test func failedAndRejectedCommitsStayUnsavedAndRetryable() async throws {
        for outcome in [CharacterCommitOutcome.failed, .rejected] {
            let model = try makeModel(current: SetupWizardFixture.sheetImages(), outcome: outcome)
            model.reload()
            try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])

            #expect(await !model.apply())

            let view = try makeView(model: model, requiresChange: true)
            #expect(view.draftStatus == .notSaved)
            #expect(view.isPrimaryActionEnabled)
        }
    }

    /// Setup commits an already valid pet without staging a new frame set. If that save fails or is
    /// declined, the card must still say the change was not saved even though there is no frame
    /// difference, and Continue must stay available for the retry.
    @Test func anUnchangedPetWhoseSaveFailedOrWasRejectedIsNotSaved() async throws {
        for outcome in [CharacterCommitOutcome.failed, .rejected] {
            let model = try makeModel(current: SetupWizardFixture.sheetImages(), outcome: outcome)
            model.reload()
            #expect(!model.isDirty)

            #expect(await !model.apply())

            let setup = try makeView(model: model, requiresChange: false)
            #expect(setup.draftStatus == .notSaved)
            #expect(setup.isPrimaryActionEnabled)
        }
    }

    @Test func discardingTheDraftRestoresTheSavedPetAndDisablesApply() async throws {
        let model = try makeModel(current: SetupWizardFixture.sheetImages())
        model.reload()
        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])
        #expect(try makeView(model: model, requiresChange: true).isPrimaryActionEnabled)

        model.discard()

        let view = try makeView(model: model, requiresChange: true)
        #expect(view.draftStatus == .currentInUse)
        #expect(!view.isPrimaryActionEnabled)
    }

    /// A rejected import leaves the saved pet in place, so the card must not claim a pending draft.
    @Test func aFailedImportOnASavedPetKeepsTheCurrentPetState() async throws {
        let model = try makeModel(current: SetupWizardFixture.sheetImages())
        model.reload()
        await model.stageFiles(at: [URL(fileURLWithPath: "/tmp/waddly-\(UUID().uuidString).png")])

        let view = try makeView(model: model, requiresChange: true)
        #expect(model.failure == .sheet(.unreadable))
        #expect(view.draftStatus == .currentInUse)
        #expect(!view.isPrimaryActionEnabled)
    }

    @Test func theTwoDraftStatesUseDistinctLabelsAndExactStatusPairs() throws {
        #expect(CharacterDraftStatus.currentInUse.messageKey == .characterStatusCurrentInUse)
        #expect(CharacterDraftStatus.notSaved.messageKey == .characterStatusNotSaved)
        #expect(CharacterDraftStatus.currentInUse.symbol != CharacterDraftStatus.notSaved.symbol)

        try expectStatus(CharacterDraftStatus.currentInUse.color, in: .aqua, red: 31, green: 122, blue: 51)
        try expectStatus(CharacterDraftStatus.currentInUse.color, in: .darkAqua, red: 74, green: 222, blue: 128)

        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            let pending = try #require(resolved(CharacterDraftStatus.notSaved.color, appearance))
            let secondary = try #require(resolved(Color(nsColor: .secondaryLabelColor), appearance))
            #expect(pending == secondary, "\(name.rawValue): a draft stays on the secondary label color")
        }
    }
}

@MainActor
private extension CharacterDraftStatusTests {
    func makeModel(
        current: PetImageSet,
        outcome: CharacterCommitOutcome = .committed
    ) -> CharacterImportModel {
        CharacterImportModel(currentImages: { current }, commit: { _ in outcome })
    }

    func makeView(model: CharacterImportModel, requiresChange: Bool) throws -> CharacterImportView {
        try CharacterImportView(
            model: model,
            localization: CaptureHarness.localized(.english),
            titleKey: .characterChangeTitle,
            primaryKey: requiresChange ? .characterApply : .setupNext,
            onPrimary: {},
            onCancel: {},
            onPreviewPaneCreated: { _ in },
            isPreviewActive: { false },
            onPreviewHostDisappear: {},
            pickFile: { nil },
            pasteboard: .general,
            primaryRequiresChange: requiresChange
        )
    }

    /// One documented Light/Dark pair of a status token, component by component.
    func expectStatus(
        _ color: Color,
        in name: NSAppearance.Name,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) throws {
        let appearance = try #require(NSAppearance(named: name))
        let actual = try #require(resolved(color, appearance))
        #expect(abs(actual.redComponent - red / 255) < 0.01, "\(name.rawValue) red")
        #expect(abs(actual.greenComponent - green / 255) < 0.01, "\(name.rawValue) green")
        #expect(abs(actual.blueComponent - blue / 255) < 0.01, "\(name.rawValue) blue")
    }
}

@MainActor
private func resolved(_ color: Color, _ appearance: NSAppearance) -> NSColor? {
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance {
        resolved = NSColor(color).usingColorSpace(.sRGB)
    }
    return resolved
}
