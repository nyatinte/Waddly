import AppKit
import Testing
@testable import WaddlyApp

/// Clipboard behaviour of the prompt hand-off. The composition itself is covered by
/// `CharacterStylePromptTests`; this suite keeps the copy action honest about failures.
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

    private func namedPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("WaddlyTests.prompt.\(UUID().uuidString)"))
    }
}
