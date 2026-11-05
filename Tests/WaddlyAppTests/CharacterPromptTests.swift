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

    @Test func theChatGPTLinkCarriesTheCurrentLanguagePrompt() throws {
        let localization = try CaptureHarness.localized(.japanese)
        let resources = SetupWizardFixture.root()
        let japanese = SpriteSheetPrompt.load(for: localization, resourcesAt: resources)
        #expect(!japanese.isEmpty)
        let japaneseURL = try #require(SpriteSheetPrompt.chatGPTURL(for: japanese))
        #expect(japaneseURL.host() == "chatgpt.com")
        // The round trip matters for the Japanese prompt: the link has to survive percent-encoding.
        #expect(queryItem(named: "q", in: japaneseURL) == japanese)

        localization.changeLanguage(.english)
        let english = SpriteSheetPrompt.load(for: localization, resourcesAt: resources)
        #expect(english != japanese)
        let englishURL = try #require(SpriteSheetPrompt.chatGPTURL(for: english))
        #expect(queryItem(named: "q", in: englishURL) == english)
    }

    @Test func openingChatGPTDoesNotTouchTheClipboard() throws {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.setString("keep this", forType: .string))
        var opened: [URL] = []
        let feedback = SpriteSheetPrompt.open("prompt", to: pasteboard) { url in
            opened.append(url)
            return true
        }
        #expect(feedback == .opened)
        #expect(!feedback.isError)
        #expect(feedback.messageKey == .setupChatGPTOpened)
        #expect(opened.count == 1)
        #expect(try queryItem(named: "q", in: #require(opened.first)) == "prompt")
        #expect(pasteboard.string(forType: .string) == "keep this")
    }

    @Test func browserFailureKeepsTheCopiedPromptAndOffersManualRecovery() {
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        var opened: [URL] = []
        let feedback = SpriteSheetPrompt.open("prompt", to: pasteboard) { url in
            opened.append(url)
            return false
        }
        #expect(opened.count == 1)
        #expect(pasteboard.string(forType: .string) == "prompt")
        #expect(feedback == .copiedAfterOpenFailed)
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
        let feedback = SpriteSheetPrompt.open(prompt, to: pasteboard) { _ in
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
        let pasteboard = try CaptureHarness.pasteboard(holdsSheet: true)
        defer { pasteboard.releaseGlobally() }
        let controller = CharacterImportWindowController(
            model: model, localization: localization, presenter: .invisible,
            pasteboard: pasteboard, promptResourcesURL: SetupWizardFixture.root(), onClose: {}
        )
        controller.focus()
        defer {
            model.discard()
            controller.close()
        }
        let content = try #require(controller.window?.contentView)
        let host = try #require(content.subviews.first as? NSHostingView<CharacterImportView>)
        #expect(model.hasStagedCandidate)
        #expect(!model.isDirty)
        model.refreshClipboardAvailability(from: pasteboard)
        #expect(model.clipboardHasImage)
        // Exercise the action used by the actual card, including its parent callback.
        var card = host.rootView.promptCard
        card.announce = { _ in }
        card.copyPrompt()
        let prompt = SpriteSheetPrompt.load(for: localization, resourcesAt: SetupWizardFixture.root())
        #expect(pasteboard.string(forType: .string) == prompt)
        #expect(!model.clipboardHasImage)
        #expect(!model.isDirty)
        #expect(commitCount == 0)

        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])
        let draft = try #require(model.stagedFrames)
        let frame = try #require(stored[.idle].first)
        try pasteboard.setData(#require(PetSpriteSheetImporter.pngData(for: frame)), forType: .png)
        model.refreshClipboardAvailability(from: pasteboard)
        #expect(model.clipboardHasImage)
        var announcements: [String] = []
        card.announce = { announcements.append($0) }
        card.openBrowser = { _ in false }
        card.openInChatGPT()
        #expect(!model.clipboardHasImage)
        #expect(pasteboard.string(forType: .string) == prompt)
        #expect(announcements == [localization.string(for: .setupOpenFailed)])
        #expect(model.isDirty)
        #expect(try CharacterImportModel.sameFrames(#require(model.stagedFrames), draft))
        #expect(CharacterImportModel.sameFrames(model.committedBaseline, stored))
        #expect(commitCount == 0)
    }

    private func queryItem(named name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func namedPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("WaddlyTests.prompt.\(UUID().uuidString)"))
    }
}
