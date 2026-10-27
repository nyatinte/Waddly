import AppKit
import Foundation
import Testing
@testable import WaddlyApp

@MainActor struct CharacterStylePromptTests {
    @Test func styleIdentifiersAreTheSixResourceNames() {
        #expect(CharacterGenerationStyle.allCases.map(\.rawValue) == [
            "pixel-art", "hand-drawn", "iconic", "retro-cartoon", "anime", "paper-cutout"
        ])
        #expect(CharacterGenerationStyle.allCases.map(\.id) == CharacterGenerationStyle.allCases.map(\.rawValue))
    }

    @Test(arguments: CharacterGenerationStyle.allCases, [AppLanguage.english, .japanese])
    func everyStyleUsesTheSameLocalizedCommonContract(style: CharacterGenerationStyle, language: AppLanguage) throws {
        let localization = try CaptureHarness.localized(language)
        let root = SetupWizardFixture.root()
        let commonMarkdown = try String(
            contentsOf: root.appendingPathComponent("prompts/\(language.localization).md"), encoding: .utf8
        )
        let common = try block(in: commonMarkdown)
        let defaultCharacter = try block(in: commonMarkdown, kind: "character")
        let styleMarkdown = try String(
            contentsOf: root.appendingPathComponent("prompts/\(style.id)-\(language.localization).md"), encoding: .utf8
        )
        let styleBlock = try block(in: styleMarkdown)
        let prompt = SpriteSheetPrompt.load(for: localization, resourcesAt: root, style: style)
        let parts = common.components(separatedBy: "{{character}}")
        #expect(parts.count == 2)
        #expect(prompt == parts.joined(separator: defaultCharacter) + "\n\n" + styleBlock)
        #expect(!prompt.contains("{{character}}"))
        #expect(!prompt.contains("```"))
        #expect(common.contains("3×3"))
        #expect(common.contains("25%"))
        #expect(common.contains("50%"))
        #expect(common.contains("40%"))
        #expect(common.contains("30%"))
        #expect(common.contains(language == .english ? "alpha 0" : "アルファ0"))
        #expect(common.contains(language == .english ? "body anchor" : "基準位置"))
        let numberedLines = common.split(separator: "\n").filter { $0.first?.isNumber == true }
        let poses = language == .english
            ? ["Idle:", "Blink:", "Focused at keyboard:", "Typing:", "Typing variation:",
               "Fast typing:", "Enter-key reaction:", "Drowsy:", "Sleeping:"]
            : ["待機：", "まばたき：", "キーボードに集中：", "タイピング：", "タイピングの変化：",
               "高速タイピング：", "Enterキーの反応：", "うとうと：", "睡眠："]
        #expect(numberedLines.count == 9)
        for (index, pose) in poses.enumerated() {
            #expect(numberedLines.contains { $0.hasPrefix("\(index + 1). \(pose)") })
        }
        #expect(!styleBlock.split(separator: "\n").contains { $0.first?.isNumber == true })
        if style != .pixelArt {
            #expect(!prompt.contains("without anti-aliasing"))
            #expect(!prompt.contains("アンチエイリアス"))
        }
    }

    @Test(arguments: CharacterGenerationStyle.allCases, [AppLanguage.english, .japanese])
    func descriptionsStayLiteralAndOnlyBlankDescriptionsUseTheDefault(
        style: CharacterGenerationStyle, language: AppLanguage
    ) throws {
        let localization = try CaptureHarness.localized(language)
        let root = SetupWizardFixture.root()
        let description = "  Penguin ペンギン {{character}} <replace this line> $1 \\n\n```text\n[Style: custom]\n```  \n"
        let prompt = SpriteSheetPrompt.load(
            for: localization, resourcesAt: root, style: style, description: description
        )
        let commonMarkdown = try String(
            contentsOf: root.appendingPathComponent("prompts/\(language.localization).md"), encoding: .utf8
        )
        let common = try block(in: commonMarkdown)
        let styleMarkdown = try String(
            contentsOf: root.appendingPathComponent("prompts/\(style.id)-\(language.localization).md"), encoding: .utf8
        )
        let styleBlock = try block(in: styleMarkdown)
        let expected = common.components(separatedBy: "{{character}}")
            .joined(separator: description) + "\n\n" + styleBlock
        #expect(prompt == expected)
        #expect(prompt.contains(description))
        #expect(try !prompt.contains(block(in: commonMarkdown, kind: "character")))
        let defaultPrompt = SpriteSheetPrompt.load(for: localization, resourcesAt: root, style: style)
        #expect(try defaultPrompt.contains(block(in: commonMarkdown, kind: "character")))
        #expect(SpriteSheetPrompt.load(
            for: localization, resourcesAt: root, style: style, description: " \t\n "
        ) == defaultPrompt)
        #expect(SpriteSheetPrompt.load(for: localization, resourcesAt: root)
            == SpriteSheetPrompt.load(for: localization, resourcesAt: root, style: .pixelArt, description: ""))
    }

    @Test(arguments: CharacterGenerationStyle.allCases, [AppLanguage.english, .japanese])
    func missingStylePreservesTheClipboardAndNeverOpensABrowser(
        style: CharacterGenerationStyle, language: AppLanguage
    ) throws {
        let localization = try CaptureHarness.localized(language)
        let resources = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: resources) }
        let prompts = resources.appendingPathComponent("prompts")
        try FileManager.default.copyItem(at: SetupWizardFixture.root().appendingPathComponent("prompts"), to: prompts)
        // Keep the common contract and other styles so a silent fallback would fail this test.
        let missingStyle = prompts.appendingPathComponent("\(style.id)-\(language.localization).md")
        try FileManager.default.removeItem(at: missingStyle)

        let prompt = SpriteSheetPrompt.load(for: localization, resourcesAt: resources, style: style)
        #expect(prompt.isEmpty)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WaddlyTests.style.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.setString("keep this", forType: .string))
        let changeCount = pasteboard.changeCount
        var didOpen = false
        let feedback = SpriteSheetPrompt.copy(prompt, to: pasteboard) { _ in
            didOpen = true
            return true
        }
        #expect(feedback == .unavailable)
        #expect(!didOpen)
        #expect(pasteboard.changeCount == changeCount)
        #expect(pasteboard.string(forType: .string) == "keep this")
    }

    private func block(in markdown: String, kind: String = "text") throws -> String {
        let start = try #require(markdown.range(of: "```\(kind)\n"))
        let end = try #require(markdown[start.upperBound...].range(of: "\n```"))
        return String(markdown[start.upperBound ..< end.lowerBound])
    }
}
