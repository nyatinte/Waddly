import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct CharacterPromptTests {
    @Test func copyUsesTheCurrentLanguageWithoutOpeningABrowser() throws {
        let localization = try CaptureHarness.localized(.japanese)
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let resources = SetupWizardFixture.root()
        let japanese = SpriteSheetPrompt.load(for: localization, resourcesAt: resources)
        #expect(!japanese.isEmpty)
        #expect(SpriteSheetPrompt.copy(japanese, to: pasteboard) == .copied)
        #expect(pasteboard.string(forType: .string) == japanese)

        localization.changeLanguage(.english)
        let english = SpriteSheetPrompt.load(for: localization, resourcesAt: resources)
        #expect(!english.isEmpty)
        #expect(english != japanese)
        #expect(SpriteSheetPrompt.copy(english, to: pasteboard) == .copied)
        #expect(pasteboard.string(forType: .string) == english)
        #expect(!english.contains("```"))
    }

    @Test func browserFailureKeepsTheCopiedPromptAndOffersManualRecovery() throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        var opened: [URL] = []
        let feedback = SpriteSheetPrompt.copy("prompt", to: pasteboard) { url in
            opened.append(url)
            return false
        }
        #expect(try opened == [#require(URL(string: "https://chatgpt.com/"))])
        #expect(pasteboard.string(forType: .string) == "prompt")
        #expect(feedback == .openFailed)
        #expect(feedback.isError)
        #expect(feedback.messageKey == .setupOpenFailed)
    }

    @Test func missingResourcesPreserveTheClipboardAndNeverOpenTheBrowser() throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.setString("keep this", forType: .string))
        let localization = try CaptureHarness.localized(.english)
        let prompt = SpriteSheetPrompt.load(for: localization, resourcesAt: nil)
        var didOpen = false
        let feedback = SpriteSheetPrompt.copy(prompt, to: pasteboard) { _ in
            didOpen = true
            return true
        }
        #expect(feedback == .unavailable)
        #expect(feedback.messageKey == .characterPromptUnavailable)
        #expect(feedback.isError)
        #expect(!didOpen)
        #expect(pasteboard.string(forType: .string) == "keep this")
    }

    @Test func changeCharacterOffersPromptsWithSavedAndStagedImagesWithoutCommitting() async throws {
        let stored = try SetupWizardFixture.sheetImages()
        var commitCount = 0
        let model = CharacterImportModel(currentImages: { stored }, commit: { _ in
            commitCount += 1
            return .committed
        })
        let localization = try CaptureHarness.localized(.english)
        let controller = CharacterImportWindowController(
            model: model, localization: localization, presenter: .invisible, onClose: {}
        )
        controller.focus()
        defer {
            model.discard()
            controller.close()
        }
        let content = try #require(controller.window?.contentView)
        let host = try #require(content.subviews.first as? NSHostingView<CharacterImportView>)
        #expect(host.rootView.showsPrompt)
        #expect(model.hasStagedCandidate)
        #expect(!model.isDirty)

        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])
        let draft = try #require(model.stagedFrames)
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let prompt = SpriteSheetPrompt.load(for: localization, resourcesAt: SetupWizardFixture.root())
        #expect(SpriteSheetPrompt.copy(prompt, to: pasteboard) == .copied)
        #expect(host.rootView.showsPrompt)
        #expect(model.isDirty)
        #expect(try CharacterImportModel.sameFrames(#require(model.stagedFrames), draft))
        #expect(CharacterImportModel.sameFrames(model.committedBaseline, stored))
        #expect(commitCount == 0)
    }

    private func namedPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("WaddlyTests.prompt.\(UUID().uuidString)"))
    }
}
