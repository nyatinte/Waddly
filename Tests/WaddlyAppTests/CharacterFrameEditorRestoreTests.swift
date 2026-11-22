import Foundation
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct CharacterFrameEditorRestoreTests {
    @Test func reopeningEditorAfterRestoreLoadsSheetOnDemandAndSavesEdits() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        app.showChangeCharacter()
        let initialController = try #require(app.characterImportWindowController)
        await initialController.model.stageFiles(at: [fixture.exampleURL])
        #expect(await initialController.model.apply())
        #expect(app.petImages.editingSource?.sheetPNGData == nil)
        initialController.close()

        app.importedImages = nil
        await app.loadSavedPetImage()
        #expect(app.petImages.editingSource?.sheetPNGData == nil)

        app.showChangeCharacter()
        let reopened = try #require(app.characterImportWindowController)
        let editor = try CharacterFrameEditorModel(
            importModel: reopened.model,
            localization: makeLocalization()
        )
        await editor.prepare()
        #expect(editor.isSheetMode)
        #expect(editor.sheet != nil)

        editor.select(.idle1)
        editor.setCropSize(192)
        let expectedIdle = try #require(editor.editing?.adjustment(for: .idle1))
        #expect(await editor.stageIntoDraft())
        editor.releaseResources()
        #expect(editor.sheet == nil)
        #expect(editor.isReleased)
        #expect(reopened.model.stagedFrames?.editingSource?.sheetPNGData == nil)

        #expect(await reopened.model.apply())
        reopened.close()
        app.importedImages = nil
        await app.loadSavedPetImage()
        let restored = try #require(app.petImages.editingSource)
        #expect(restored.editing.adjustment(for: .idle1) == expectedIdle)
        #expect(restored.sheetPNGData == nil)
        #expect(restored.sheetFileURL == fixture.directory.appendingPathComponent("source-sheet.png"))
        #expect(restored.loadSheetPNGData() != nil)
        #expect(FileManager.default.fileExists(
            atPath: fixture.directory.appendingPathComponent("source-sheet.png").path
        ))
    }
}
