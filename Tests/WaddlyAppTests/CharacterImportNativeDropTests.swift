import AppKit
import Testing
@testable import WaddlyApp

@Suite(.serialized) @MainActor struct CharacterImportNativeDropTests {
    @Test func nativeDropAdapterPreservesEveryURLAndCallsItsHandlerOnce() throws {
        let view = PetImageDropView(frame: .zero)
        view.shouldPreserveUnsupportedDropURLs = { true }
        var received: [[URL]] = []
        view.onDrop = { received.append($0) }
        let png = try SetupWizardFixture.sheetURL()
        let jpg = URL(fileURLWithPath: "/tmp/native-drop.jpg")
        let pasteboard = try fileDropPasteboard([png, jpg])

        #expect(view.performFileURLDrop(from: pasteboard))
        #expect(received.count == 1)
        #expect(received.first == [png, jpg])
    }

    @Test func windowAndEmbeddedPreviewDropsReachSharedValidation() async throws {
        let saved = try SetupWizardFixture.sheetImages()
        let wizard = try SetupWizardFixture.makeWizard()
        defer { wizard.close() }
        let model = CharacterImportModel(currentImages: { saved }, commit: { _ in .committed })
        let controller = CharacterImportWindowController(
            model: model,
            localization: wizard.localization,
            presenter: .invisible,
            onClose: {}
        )
        defer {
            model.discard()
            controller.close()
        }
        controller.focus()
        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])
        let staged = try #require(model.stagedFrames)
        let root = try #require(controller.window?.contentView as? PetImageDropView)
        let pane = try #require(SetupWizardFixture.descendants(of: root).compactMap { $0 as? SetupPreviewPane }.first)
        let png = try SetupWizardFixture.sheetURL()
        let jpg = URL(fileURLWithPath: "/tmp/native-mixed-drop.jpg")

        #expect(try root.performFileURLDrop(from: fileDropPasteboard([png, jpg])))
        #expect(await waitUntil { model.failure == .multipleFiles })
        #expect(try CharacterImportModel.sameFrames(#require(model.stagedFrames), staged))

        #expect(try pane.performFileURLDrop(from: fileDropPasteboard([jpg])))
        #expect(await waitUntil { model.failure == .sheet(.notPNG) })
        #expect(try CharacterImportModel.sameFrames(#require(model.stagedFrames), staged))
    }

    @Test func removingTheSharedPreviewHostStopsPlaybackInBothWindows() async throws {
        let saved = try SetupWizardFixture.sheetImages()
        let changeWizard = try SetupWizardFixture.makeWizard()
        defer { changeWizard.close() }
        let changeModel = CharacterImportModel(currentImages: { saved }, commit: { _ in .committed })
        let changeWindow = CharacterImportWindowController(
            model: changeModel,
            localization: changeWizard.localization,
            presenter: .invisible,
            onClose: {}
        )
        changeWindow.focus()
        let changePane = try #require(await waitForPreviewPane(in: changeWindow.window?.contentView))
        #expect(changePane.isPlayingPreview)
        changeWindow.close()
        #expect(!changePane.isPlayingPreview)

        let setupState = SetupWizardFixture.State()
        setupState.images = saved
        let setup = try SetupWizardFixture.makeWizard(state: setupState)
        setup.beginCharacterImport()
        let embeddedPane = try #require(await waitForPreviewPane(
            in: setup.window?.contentView,
            excluding: setup.previewPane
        ))
        #expect(embeddedPane.isPlayingPreview)
        #expect(setup.embeddedCharacterPreviewPane === embeddedPane)
        await setup.commitCharacterImportAndContinue().value
        #expect(!setup.isComposingCharacter)
        await waitForPlaybackStop(embeddedPane)
        #expect(!embeddedPane.isPlayingPreview)
    }

    @Test func setupDropAdaptersPreserveLegacyFilteringButValidateSharedDrops() async throws {
        let wizard = try SetupWizardFixture.makeWizard()
        defer {
            wizard.characterImportModel.discard()
            wizard.close()
        }
        let root = try #require(wizard.window?.contentView as? PetImageDropView)
        let jpg = URL(fileURLWithPath: "/tmp/native-setup.jpg")
        #expect(try !root.performFileURLDrop(from: fileDropPasteboard([jpg])))
        #expect(!wizard.isComposingCharacter)

        wizard.beginCharacterImport()
        let png = try SetupWizardFixture.sheetURL()
        await wizard.characterImportModel.stageFiles(at: [png])
        let staged = try #require(wizard.characterImportModel.stagedFrames)
        #expect(try root.performFileURLDrop(from: fileDropPasteboard([png, jpg])))
        #expect(await waitUntil { wizard.characterImportModel.failure == .multipleFiles })
        #expect(try CharacterImportModel.sameFrames(
            #require(wizard.characterImportModel.stagedFrames), staged
        ))

        #expect(try wizard.previewPane.performFileURLDrop(from: fileDropPasteboard([jpg])))
        #expect(await waitUntil { wizard.characterImportModel.failure == .sheet(.notPNG) })
    }
}

@MainActor
private func waitForPlaybackStop(_ pane: SetupPreviewPane) async {
    for _ in 0 ..< 500 where pane.isPlayingPreview {
        await Task.yield()
    }
}

@MainActor
private func waitForPreviewPane(in root: NSView?, excluding: SetupPreviewPane? = nil) async -> SetupPreviewPane? {
    guard let root else { return nil }
    for _ in 0 ..< 500 {
        let pane = SetupWizardFixture.descendants(of: root).compactMap { $0 as? SetupPreviewPane }
            .first { $0 !== excluding }
        if let pane, pane.isPlayingPreview {
            return pane
        }
        await Task.yield()
    }
    return SetupWizardFixture.descendants(of: root).compactMap { $0 as? SetupPreviewPane }
        .first { $0 !== excluding }
}

@MainActor
private func fileDropPasteboard(_ urls: [URL]) throws -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("WaddlyTests.drop.\(UUID().uuidString)"))
    pasteboard.clearContents()
    #expect(pasteboard.writeObjects(urls.map { $0 as NSURL }))
    return pasteboard
}

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0 ..< 500 {
        if condition() {
            return true
        }
        await Task.yield()
    }
    return condition()
}
