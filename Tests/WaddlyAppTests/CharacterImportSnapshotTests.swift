import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Documentation captures for the shared character-import screen, both hosts. Opt-in via
/// `WADDLY_CAPTURE_CHARACTER_IMPORT=1`; with the variable unset the suite does nothing. See
/// `docs/images/character-import/README.md` for provenance and what these renders do not claim.
@Suite(.serialized) @MainActor struct CharacterImportSnapshotTests {
    @Test func capturesChangeCharacterSurfaces() async throws {
        guard CaptureHarness.isEnabled else { return }
        try CaptureHarness.prepare()
        for language in [AppLanguage.english, .japanese] {
            for dark in [false, true] {
                try await captureChangeCharacter(language: language, dark: dark)
            }
        }
    }

    @Test func capturesSavedCharacterEditingEntry() throws {
        guard CaptureHarness.isEnabled else { return }
        try CaptureHarness.prepare()
        for language in [AppLanguage.english, .japanese] {
            for dark in [false, true] {
                try captureSavedCharacter(language: language, dark: dark)
            }
        }
    }

    @Test func capturesRejectedCommitFeedback() async throws {
        guard CaptureHarness.isEnabled else { return }
        try CaptureHarness.prepare()
        for language in [AppLanguage.english, .japanese] {
            for dark in [false, true] {
                try await captureRejectedCommit(language: language, dark: dark)
            }
        }
    }

    @Test func capturesSetupPetStepSurfaces() async throws {
        guard CaptureHarness.isEnabled else { return }
        try CaptureHarness.prepare()
        for language in [AppLanguage.english, .japanese] {
            for dark in [false, true] {
                try await captureSetupPetStep(language: language, dark: dark)
            }
        }
    }
}

@MainActor
private extension CharacterImportSnapshotTests {
    func captureRejectedCommit(language: AppLanguage, dark: Bool) async throws {
        let frames = try SetupWizardFixture.sheetImages()
        let model = CharacterImportModel(currentImages: { frames }, commit: { _ in .rejected })
        let localization = try CaptureHarness.localized(language)
        let controller = CharacterImportWindowController(
            model: model,
            localization: localization,
            presenter: .invisible,
            onClose: {}
        )
        controller.focus()
        defer { controller.close() }
        #expect(await !model.apply())
        await Task.yield()
        try CaptureHarness.write(
            #require(controller.window?.contentView),
            dark: dark,
            named: "change-rejected-commit-\(CaptureHarness.suffix(language, dark))"
        )
    }

    func captureSavedCharacter(language: AppLanguage, dark: Bool) throws {
        var frames = try SetupWizardFixture.sheetImages()
        frames[.idle].append(frames[.typing][0])
        frames[.typing].removeFirst()
        let model = CharacterImportModel(currentImages: { frames }, commit: { _ in .committed })
        let localization = try CaptureHarness.localized(language)
        let controller = CharacterImportWindowController(
            model: model,
            localization: localization,
            presenter: .invisible,
            onClose: {}
        )
        controller.focus()
        defer { controller.close() }
        try CaptureHarness.write(
            #require(controller.window?.contentView),
            dark: dark,
            named: "change-saved-character-\(CaptureHarness.suffix(language, dark))"
        )
    }

    func captureChangeCharacter(language: AppLanguage, dark: Bool) async throws {
        let model = CharacterImportModel(currentImages: { PetImageSet() }, commit: { _ in .committed })
        let controller = try CharacterImportWindowController(
            model: model,
            localization: CaptureHarness.localized(language),
            presenter: .invisible,
            onClose: {}
        )
        defer {
            // Closing with a staged draft now asks first; the harness discards instead of prompting.
            controller.model.discard()
            controller.close()
        }
        let content = try #require(controller.window?.contentView)
        let tag = CaptureHarness.suffix(language, dark)

        try CaptureHarness.write(content, dark: dark, named: "change-empty-\(tag)")
        try await captureDropAndClipboardStates(model: model, content: content, dark: dark, tag: tag)
        try await captureValidAndInvalidStates(model: model, content: content, dark: dark, tag: tag)
        try captureEditing(
            model: model,
            controller: controller,
            language: language,
            dark: dark,
            tag: tag
        )
    }

    /// The drag-eligible highlight, the ready Paste affordance, and the clipboard-empty explanation.
    func captureDropAndClipboardStates(
        model: CharacterImportModel,
        content: NSView,
        dark: Bool,
        tag: String
    ) async throws {
        model.setDropTargeted(true)
        try CaptureHarness.write(content, dark: dark, named: "change-drag-hover-\(tag)")
        model.setDropTargeted(false)

        try model.refreshClipboardAvailability(from: CaptureHarness.pasteboard(holdsSheet: true))
        try CaptureHarness.write(content, dark: dark, named: "change-clipboard-ready-\(tag)")

        let emptyPasteboard = try CaptureHarness.pasteboard(holdsSheet: false)
        model.refreshClipboardAvailability(from: emptyPasteboard)
        await model.stageClipboard(from: emptyPasteboard)
        try CaptureHarness.write(content, dark: dark, named: "change-clipboard-empty-\(tag)")
    }

    /// The staged valid sheet in both preview modes, then an invalid import that keeps the draft.
    func captureValidAndInvalidStates(
        model: CharacterImportModel,
        content: NSView,
        dark: Bool,
        tag: String
    ) async throws {
        try await model.stageFiles(at: [CaptureHarness.sheetURL()])
        CaptureHarness.showStagedFrames(model, in: content)
        // Let the preview player publish its first frame on the main actor before capturing.
        try await Task.sleep(for: .milliseconds(250))
        try CaptureHarness.write(content, dark: dark, named: "change-valid-\(tag)")
        if let pane = CaptureHarness.previewPane(in: content) {
            CaptureHarness.setPreviewPane(pane, cells: true)
            try CaptureHarness.write(content, dark: dark, named: "change-valid-nine-cells-\(tag)")
            CaptureHarness.setPreviewPane(pane, cells: false)
        }
        await model.stageFiles(at: [URL(fileURLWithPath: "/tmp/waddly-capture-missing.png")])
        try CaptureHarness.write(content, dark: dark, named: "change-invalid-\(tag)")
    }

    /// The advanced per-frame editor over the same staged draft.
    func captureEditing(
        model: CharacterImportModel,
        controller: CharacterImportWindowController,
        language: AppLanguage,
        dark: Bool,
        tag: String
    ) throws {
        controller.frameEditorModel.setThumbnails(
            CharacterFrameEditor.thumbnails(from: model.stagedFrames)
        )
        let host = try NSHostingView(rootView: CharacterFrameEditor(
            importModel: model,
            editor: controller.frameEditorModel,
            localization: CaptureHarness.localized(language)
        ))
        host.frame = NSRect(
            x: 0,
            y: 0,
            width: AnimationSettingsMetrics.contentMinSize.width + 80,
            height: AnimationSettingsMetrics.contentMinSize.height + 64
        )
        try CaptureHarness.write(host, dark: dark, named: "change-editing-\(tag)")
    }

    /// The same shared screen inside the Setup Pet step, with the progress row above it.
    func captureSetupPetStep(language: AppLanguage, dark: Bool) async throws {
        let state = SetupWizardFixture.State()
        let wizard = try SetupWizardFixture.makeWizard(
            language: language,
            state: state,
            demoURL: CaptureHarness.sheetURL()
        )
        defer { wizard.close() }
        wizard.beginCharacterImport()
        let content = try #require(wizard.window?.contentView)
        let tag = CaptureHarness.suffix(language, dark)

        try CaptureHarness.write(content, dark: dark, named: "setup-empty-\(tag)")
        try await wizard.characterImportModel.stageFiles(at: [CaptureHarness.sheetURL()])
        CaptureHarness.showStagedFrames(wizard.characterImportModel, in: content)
        try await Task.sleep(for: .milliseconds(250))
        try CaptureHarness.write(content, dark: dark, named: "setup-valid-\(tag)")
    }
}
