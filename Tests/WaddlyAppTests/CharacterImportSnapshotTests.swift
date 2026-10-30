import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Captures for the shared character-import screen, both hosts. Opt-in via
/// `WADDLY_CAPTURE_CHARACTER_IMPORT=1`; with the variable unset the suite does nothing.
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

    @Test func capturesSavedCharacterEditingEntry() async throws {
        guard CaptureHarness.isEnabled else { return }
        try CaptureHarness.prepare()
        for language in [AppLanguage.english, .japanese] {
            for dark in [false, true] {
                try await captureSavedCharacter(language: language, dark: dark)
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

    @Test func capturesFrameEditorSurfaces() throws {
        guard CaptureHarness.isEnabled else { return }
        try CaptureHarness.prepare()
        for language in [AppLanguage.english, .japanese] {
            for dark in [false, true] {
                try captureFrameEditor(language: language, dark: dark)
            }
        }
    }

    @Test func capturesFrameEditorLegacyAndCompactSurfaces() throws {
        guard CaptureHarness.isEnabled else { return }
        try CaptureHarness.prepare()
        for language in [AppLanguage.english, .japanese] {
            for dark in [false, true] {
                try captureFrameEditorLegacy(language: language, dark: dark)
                try captureFrameEditorCompact(language: language, dark: dark)
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

    /// The finished step in both monitoring outcomes: the result card is the screen's only group, so
    /// both the confirmed and the pending row are worth a capture.
    @Test func capturesSetupCompletedSurfaces() throws {
        guard CaptureHarness.isEnabled else { return }
        try CaptureHarness.prepare()
        for language in [AppLanguage.english, .japanese] {
            for dark in [false, true] {
                for ready in [true, false] {
                    try captureSetupCompleted(language: language, dark: dark, ready: ready)
                }
            }
        }
    }

    /// Setup opened over a saved pet: "Currently in use" with Continue still available.
    @Test func capturesSetupSavedCharacter() async throws {
        guard CaptureHarness.isEnabled else { return }
        try CaptureHarness.prepare()
        for language in [AppLanguage.english, .japanese] {
            for dark in [false, true] {
                try await captureSetupSavedCharacter(language: language, dark: dark)
            }
        }
    }

    /// The Pet step's inline import failure. The monitoring states live in
    /// `SetupMonitoringSnapshotTests`; this is the one setup status surface without a home there.
    @Test func capturesSetupPetImportError() async throws {
        guard CaptureHarness.isEnabled else { return }
        try CaptureHarness.prepare()
        for language in [AppLanguage.english, .japanese] {
            for dark in [false, true] {
                try await captureSetupPetError(language: language, dark: dark)
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
        try CaptureHarness.showStagedFrames(model, in: #require(controller.window?.contentView))
        try await Task.sleep(for: .milliseconds(250))
        try CaptureHarness.write(
            #require(controller.window?.contentView),
            dark: dark,
            named: "change-rejected-commit-\(CaptureHarness.suffix(language, dark))"
        )
    }

    func captureSavedCharacter(language: AppLanguage, dark: Bool) async throws {
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
        #expect(model.stagedFrames?.isComplete == true)
        try CaptureHarness.showStagedFrames(model, in: #require(controller.window?.contentView))
        // The preview player publishes its first frame off the main run loop.
        try await Task.sleep(for: .milliseconds(250))
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
        _ = controller
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

    /// The sprite-frame crop and alignment editor over the same staged sheet.
    func captureFrameEditor(language: AppLanguage, dark: Bool) throws {
        let tag = CaptureHarness.suffix(language, dark)
        let data = try Data(contentsOf: CaptureHarness.sheetURL())
        let candidate = try #require(try? PetSpriteSheetImporter.inspect(data).get())
        let sheet = try #require(PetFrameSourceDecoder.sheetImage(from: candidate.sheetPNGData))
        let localization = try CaptureHarness.localized(language)
        let editor = CharacterFrameEditorModel(
            frames: candidate.images,
            localization: localization,
            sheet: sheet
        )

        try writeEditor(editor, localization: localization, dark: dark, named: "frame-editor-default-\(tag)")

        editor.select(.typing2)
        editor.setCropSize(candidate.cellSize - 24)
        editor.setOffsetX(6)
        try writeEditor(editor, localization: localization, dark: dark, named: "frame-editor-crop-\(tag)")

        editor.tool = .align
        editor.select(.typing1)
        // Shift the crop window across the cell boundary to show the neighbouring-cell warning.
        editor.setCropOriginX(512 - 20)
        editor.setOffsetY(-8)
        try writeEditor(editor, localization: localization, dark: dark, named: "frame-editor-align-\(tag)")
    }

    /// A saved pet without its original sheet falls back to honest per-frame editing.
    func captureFrameEditorLegacy(language: AppLanguage, dark: Bool) throws {
        let tag = CaptureHarness.suffix(language, dark)
        let frames = try SetupWizardFixture.sheetImages()
        let localization = try CaptureHarness.localized(language)
        let editor = CharacterFrameEditorModel(frames: frames, localization: localization)
        editor.select(.idle2)
        editor.setOffsetX(5)
        editor.setOffsetY(-4)
        try writeEditor(
            editor,
            localization: localization,
            dark: dark,
            named: "frame-editor-legacy-\(tag)"
        )
    }

    /// The adaptive layout on a narrower display keeps the canvas usable and the inspector scrollable.
    func captureFrameEditorCompact(language: AppLanguage, dark: Bool) throws {
        let tag = CaptureHarness.suffix(language, dark)
        let data = try Data(contentsOf: CaptureHarness.sheetURL())
        let candidate = try #require(try? PetSpriteSheetImporter.inspect(data).get())
        let sheet = try #require(PetFrameSourceDecoder.sheetImage(from: candidate.sheetPNGData))
        let localization = try CaptureHarness.localized(language)
        let editor = CharacterFrameEditorModel(
            frames: candidate.images,
            localization: localization,
            sheet: sheet
        )
        editor.select(.typing3)
        editor.setCropSize(candidate.cellSize - 32)
        try writeEditor(
            editor,
            localization: localization,
            dark: dark,
            named: "frame-editor-compact-\(tag)",
            size: FrameEditorMetrics.minimumSize
        )

        // The compact layout must also fit the full neighbour warning and the align controls.
        editor.tool = .align
        editor.select(.typing1)
        editor.setCropOriginX(512 - 20)
        editor.setOffsetY(-8)
        try writeEditor(
            editor,
            localization: localization,
            dark: dark,
            named: "frame-editor-compact-align-\(tag)",
            size: FrameEditorMetrics.minimumSize
        )
    }

    func writeEditor(
        _ editor: CharacterFrameEditorModel,
        localization: LocalizationController,
        dark: Bool,
        named name: String,
        size: NSSize = FrameEditorMetrics.preferredSize
    ) throws {
        let host = NSHostingView(rootView: CharacterFrameEditor(
            model: editor,
            localization: localization,
            size: size
        )
        .environment(\.colorScheme, dark ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        try CaptureHarness.write(host, dark: dark, named: name)
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
        let content = try #require(wizard.window?.contentView)
        let tag = CaptureHarness.suffix(language, dark)

        try CaptureHarness.write(content, dark: dark, named: "setup-empty-\(tag)")
        try await wizard.characterImportModel.stageFiles(at: [CaptureHarness.sheetURL()])
        CaptureHarness.showStagedFrames(wizard.characterImportModel, in: content)
        try await Task.sleep(for: .milliseconds(250))
        try CaptureHarness.write(content, dark: dark, named: "setup-valid-\(tag)")
    }

    /// The completion page, reached the way a user reaches it: with a stored pet, landed on the
    /// final step. `ready` picks a confirmed reaction or the incomplete-recovery variant.
    func captureSetupCompleted(language: AppLanguage, dark: Bool, ready: Bool) throws {
        let state = SetupWizardFixture.State()
        state.images = try SetupWizardFixture.sheetImages()
        let wizard = try SetupWizardFixture.makeWizard(
            language: language,
            state: state,
            demoURL: CaptureHarness.sheetURL(),
            granted: ready,
            receiving: ready,
            observedReaction: ready
        )
        defer { wizard.close() }
        wizard.setStep(.completed)
        try CaptureHarness.write(
            #require(wizard.window?.contentView),
            dark: dark,
            named: "setup-complete-\(ready ? "ready" : "pending")-\(CaptureHarness.suffix(language, dark))"
        )
    }

    /// Setup opened over a saved pet: the card must say it is in use, and Continue stays available.
    func captureSetupSavedCharacter(language: AppLanguage, dark: Bool) async throws {
        let state = SetupWizardFixture.State()
        state.images = try SetupWizardFixture.sheetImages()
        let wizard = try SetupWizardFixture.makeWizard(
            language: language,
            state: state,
            demoURL: CaptureHarness.sheetURL()
        )
        defer { wizard.close() }
        wizard.beginCharacterImport()
        let content = try #require(wizard.window?.contentView)
        CaptureHarness.showStagedFrames(wizard.characterImportModel, in: content)
        try await Task.sleep(for: .milliseconds(250))
        try CaptureHarness.write(
            content,
            dark: dark,
            named: "setup-saved-\(CaptureHarness.suffix(language, dark))"
        )
    }

    /// The Pet step's inline import failure, rendered from the same shell as the saved state.
    func captureSetupPetError(language: AppLanguage, dark: Bool) async throws {
        let wizard = try SetupWizardFixture.makeWizard(language: language)
        defer { wizard.close() }
        await wizard.characterImportModel.stageFiles(at: [URL(fileURLWithPath: "/invalid.jpg")])
        try CaptureHarness.write(
            #require(wizard.window?.contentView),
            dark: dark,
            named: "setup-pet-error-\(CaptureHarness.suffix(language, dark))"
        )
    }
}
