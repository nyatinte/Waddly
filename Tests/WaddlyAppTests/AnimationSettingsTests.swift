import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp
import WaddlyCore

/// The advanced per-frame editor surface: the Change Character window's lifecycle, the fixed content
/// minimum, and that advanced edits land in the staged draft rather than the committed pet.
@Suite(.serialized) @MainActor struct AnimationSettingsTests {
    /// Closing releases the app's reference and detaches the hosted SwiftUI view. Reopening builds a
    /// fresh model on the pet that is committed now.
    @Test func releaseOnCloseAndRebuildOnReopen() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.showChangeCharacter()
        let window = try #require(app.characterImportWindowController?.window)
        #expect(window.contentView?.subviews.contains { $0 is NSHostingView<CharacterImportView> } == true)
        let first = try #require(app.characterImportWindowController)

        window.close()
        #expect(app.characterImportWindowController == nil)
        #expect(window.contentView == nil)

        app.showChangeCharacter()
        let second = try #require(app.characterImportWindowController)
        #expect(second !== first)
    }

    /// The editor's minimum must be a *content* minimum that fits all four fixed rows plus the
    /// instructions. The old frame-based `minSize` subtracted the title bar and clipped the last row.
    @Test func minimumContentFitsAllFourRows() {
        let minimum = AnimationSettingsMetrics.contentMinSize
        let rows = AnimationSettingsMetrics.rowHeight * CGFloat(PetImageCategory.allCases.count)
        let gaps = AnimationSettingsMetrics.rowSpacing * CGFloat(PetImageCategory.allCases.count + 1)
        #expect(minimum.height >= rows + gaps
            + AnimationSettingsMetrics.instructionBlockHeight + AnimationSettingsMetrics.contentInset * 2)
        // 640 was the old frame height, which left the content shorter than four rows.
        #expect(minimum.height > 640)
    }

    /// An advanced edit is staged, not committed: it reaches the change flow's own draft and leaves
    /// the saved pet untouched until Apply.
    @Test func advancedEditorStagesFramesWithoutCommitting() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.showChangeCharacter()
        let controller = try #require(app.characterImportWindowController)
        await controller.model.stageFiles(at: [fixture.exampleURL])
        let stagedIdleBefore = try #require(controller.model.stagedFrames)[.idle].count
        let committedIdleBefore = app.petImages[.idle].count
        let frame = try #require(app.petImages[.idle].first)
        let pngURL = fixture.directory.appendingPathComponent("staged.png")
        try #require(PetSpriteSheetImporter.pngData(for: frame)).write(to: pngURL)

        controller.frameEditorModel.drop([pngURL], on: .idle)

        #expect(await waitForStagedIdle(controller.model, count: stagedIdleBefore + 1))
        #expect(app.petImages[.idle].count == committedIdleBefore)
    }
}

private extension AnimationSettingsTests {
    /// The advanced editor's add decodes on a detached task, so poll until the draft updates.
    func waitForStagedIdle(_ model: CharacterImportModel, count: Int) async -> Bool {
        for _ in 0 ..< 300 {
            if model.stagedFrames?[.idle].count == count {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
