import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct CharacterImportContractTests {
    /// The crop editor's Done only replaces the staged draft. Parent Apply is still the single write,
    /// and a legacy frame set without a sheet stays editable in the same draft.
    @Test func frameEditsStageIntoDraftAndApplyCommitsThem() async throws {
        var stored = try SetupWizardFixture.sheetImages()
        let persisted = stored
        var commitCount = 0
        let model = CharacterImportModel(
            currentImages: { stored },
            commit: { stored = $0; commitCount += 1; return .committed }
        )

        model.reload()
        #expect(model.stagedFrames != nil)
        #expect(!model.isDirty)

        let staged = try #require(model.stagedFrames)
        var edited = staged
        edited[.idle][0] = try #require(edited[.typing].first)
        model.stageFrameEdited(edited)

        #expect(model.isDirty)
        #expect(commitCount == 0)
        #expect(CharacterImportModel.sameFrames(stored, persisted))

        model.discard()
        #expect(!model.isDirty)
        #expect(CharacterImportModel.sameFrames(stored, persisted))

        model.stageFrameEdited(edited)
        #expect(await model.apply())
        #expect(commitCount == 1)
        #expect(CharacterImportModel.sameFrames(stored, edited))
    }

    @Test func repeatedCloseWaitsForTheOutstandingDiscardConfirmation() async throws {
        let wizard = try SetupWizardFixture.makeWizard()
        defer { wizard.close() }
        let model = CharacterImportModel(currentImages: { PetImageSet() }, commit: { _ in .committed })
        var respond: ((NSApplication.ModalResponse) -> Void)?
        var alertCount = 0
        var closeCount = 0
        var presenter = WindowPresenter.invisible
        presenter.presentAlert = { _, _, response in
            alertCount += 1
            respond = response
        }
        let controller = CharacterImportWindowController(
            model: model, localization: wizard.localization, presenter: presenter,
            onClose: { closeCount += 1 }
        )
        defer { controller.close() }
        controller.focus()
        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])
        let window = try #require(controller.window)
        #expect(model.isDirty)
        #expect(!controller.windowShouldClose(window))
        let cancel = try #require(respond)
        #expect(!controller.windowShouldClose(window))
        #expect(alertCount == 1)
        cancel(.alertSecondButtonReturn)
        #expect(window.isVisible)
        #expect(model.isDirty)
        #expect(closeCount == 0)
        #expect(!controller.windowShouldClose(window))
        #expect(alertCount == 2)
        let confirm = try #require(respond)
        confirm(.alertFirstButtonReturn)
        #expect(!window.isVisible)
        #expect(closeCount == 1)
    }

    @Test func rejectedCommitIsNotReportedAsPersistenceFailure() async throws {
        let model = CharacterImportModel(currentImages: { PetImageSet() }, commit: { _ in .rejected })
        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])

        #expect(await !model.apply())
        #expect(!model.commitFailed)
        #expect(model.commitRejected)
        #expect(model.stagedFrames?.isComplete == true)
    }

    @Test func oversizedPNGReportsTheFileSizeFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaddlyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                Issue.record(error)
            }
        }
        let url = directory.appendingPathComponent("oversized.png")
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        let file = try FileHandle(forWritingTo: url)
        try file.seek(toOffset: UInt64(PetSpriteSheetImporter.maximumFileSize + 1))
        try file.write(contentsOf: Data([0]))
        try file.close()

        let model = CharacterImportModel(currentImages: { PetImageSet() }, commit: { _ in .committed })
        await model.stageFiles(at: [url])

        #expect(model.failure == .sheet(.fileTooLarge))
        #expect(model.stagedFrames == nil)
    }
}
