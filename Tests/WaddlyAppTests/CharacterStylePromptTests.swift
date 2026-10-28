import Foundation
import Testing
@testable import WaddlyApp

/// The prompt is a shared 3×3 contract plus one style block. These tests keep the contract single,
/// the style blocks distinct, and every failure mode closed instead of half-copied.
@Suite(.serialized) @MainActor struct CharacterStylePromptTests {
    @Test func catalogKeepsTheDocumentedOrderAndUniqueSlugs() {
        #expect(CharacterStyle.allCases.map(\.rawValue) == [
            "pixel-art", "hand-drawn", "iconic", "retro-cartoon", "anime", "paper-cutout"
        ])
        #expect(Set(CharacterStyle.allCases.map(\.id)).count == CharacterStyle.allCases.count)
    }

    @Test(arguments: [AppLanguage.japanese, .english], CharacterStyle.allCases)
    func promptIsExactlyTheSharedContractPlusTheSelectedStyle(
        language: AppLanguage,
        style: CharacterStyle
    ) throws {
        let resources = SetupWizardFixture.root()
        let template = try block("prompts/\(language.localization).md", in: resources)
        let fallback = try block("prompts/\(language.localization).md", in: resources, kind: "character")
        let guidance = try block("prompts/\(style.rawValue)-\(language.localization).md", in: resources)
        let contract = template.replacingOccurrences(of: "{{character}}", with: fallback)
        let prompt = try SpriteSheetPrompt.load(
            for: CaptureHarness.localized(language), resourcesAt: resources, style: style
        )
        #expect(prompt == contract + "\n\n" + guidance)
        #expect(!prompt.contains("```"))
        #expect(guidance.hasPrefix("[Art style]"))
    }

    @Test(arguments: [AppLanguage.japanese, .english])
    func everyStyleShipsADistinctGuidanceBlock(language: AppLanguage) throws {
        let resources = SetupWizardFixture.root()
        var guidanceByStyle: [String: String] = [:]
        for style in CharacterStyle.allCases {
            guidanceByStyle[style.rawValue] = try block(
                "prompts/\(style.rawValue)-\(language.localization).md", in: resources
            )
        }
        #expect(guidanceByStyle.count == CharacterStyle.allCases.count)
        #expect(Set(guidanceByStyle.values).count == CharacterStyle.allCases.count)
    }

    @Test(arguments: [AppLanguage.japanese, .english])
    func sharedContractKeepsTheNinePoseRulesOutOfTheStyleBlocks(language: AppLanguage) throws {
        let contract = try block("prompts/\(language.localization).md", in: SetupWizardFixture.root())
        let required = language == .japanese
            ? ["3×3", "透明", "9コマ", "Enter"]
            : ["3×3", "transparent", "nine cells", "Enter"]
        for phrase in required {
            #expect(contract.localizedCaseInsensitiveContains(phrase), "missing \(phrase)")
        }
        // Style-dependent rules belong to the style files, never to the shared contract.
        let styleSpecific = language == .japanese
            ? ["アンチエイリアス", "セルシェーディング"]
            : ["anti-aliasing", "cel shading"]
        for phrase in styleSpecific {
            #expect(!contract.localizedCaseInsensitiveContains(phrase), "leaked \(phrase)")
        }
    }

    @Test(arguments: [AppLanguage.japanese, .english])
    func descriptionReplacesTheCharacterLineAndFallsBackWhenEmpty(language: AppLanguage) throws {
        let localization = try CaptureHarness.localized(language)
        let resources = SetupWizardFixture.root()
        let blank = SpriteSheetPrompt.load(for: localization, resourcesAt: resources, style: .anime)
        let described = SpriteSheetPrompt.load(
            for: localization,
            resourcesAt: resources,
            style: .anime,
            character: "  A round blue penguin.  "
        )
        #expect(blank.contains("{{character}}") == false)
        #expect(described.contains("{{character}}") == false)
        #expect(described.contains("A round blue penguin."))
        #expect(described != blank)
        #expect(!described.contains("  A round blue penguin.  "))
    }

    @Test func aContractWithoutThePlaceholderFailsClosed() throws {
        let resources = try makeResources([
            "en.md": markdown("SHARED WITHOUT A SLOT"),
            "anime-en.md": markdown("[Art style]\n- cel shading")
        ])
        defer { try? FileManager.default.removeItem(at: resources) }
        #expect(try SpriteSheetPrompt.load(
            for: CaptureHarness.localized(.english), resourcesAt: resources, style: .anime
        ) == "")
    }

    @Test func missingStyleResourceFailsClosed() throws {
        let resources = try makeResources(["en.md": markdown("SHARED")])
        defer { try? FileManager.default.removeItem(at: resources) }
        #expect(try SpriteSheetPrompt.load(
            for: CaptureHarness.localized(.english), resourcesAt: resources, style: .anime
        ) == "")
    }

    @Test func missingCharacterFallbackFailsClosed() throws {
        let resources = try makeResources([
            "en.md": "# Prompt\n\n```text\nHello {{character}}\n```\n",
            "anime-en.md": markdown("[Art style]\n- cel shading")
        ])
        defer { try? FileManager.default.removeItem(at: resources) }
        #expect(try SpriteSheetPrompt.load(
            for: CaptureHarness.localized(.english), resourcesAt: resources, style: .anime
        ) == "")
    }

    @Test func missingSharedContractFailsClosed() throws {
        let resources = try makeResources(["anime-en.md": markdown("[Art style]\n- cel shading")])
        defer { try? FileManager.default.removeItem(at: resources) }
        #expect(try SpriteSheetPrompt.load(
            for: CaptureHarness.localized(.english), resourcesAt: resources, style: .anime
        ) == "")
    }

    @Test func ambiguousOrEmptyBlockFailsClosed() throws {
        let duplicated = try makeResources([
            "en.md": markdown("SHARED") + "\n" + markdown("SECOND"),
            "anime-en.md": markdown("[Art style]\n- cel shading")
        ])
        let empty = try makeResources(["en.md": markdown("SHARED"), "anime-en.md": markdown(" ")])
        defer {
            try? FileManager.default.removeItem(at: duplicated)
            try? FileManager.default.removeItem(at: empty)
        }
        let localization = try CaptureHarness.localized(.english)
        #expect(SpriteSheetPrompt.load(for: localization, resourcesAt: duplicated, style: .anime) == "")
        #expect(SpriteSheetPrompt.load(for: localization, resourcesAt: empty, style: .anime) == "")
    }

    @Test func everyStyleHasItsOwnPromptText() throws {
        let localization = try CaptureHarness.localized(.english)
        let prompts = CharacterStyle.allCases.map {
            SpriteSheetPrompt.load(for: localization, resourcesAt: SetupWizardFixture.root(), style: $0)
        }
        #expect(prompts.allSatisfy { !$0.isEmpty })
        #expect(Set(prompts).count == CharacterStyle.allCases.count)
    }

    @Test func localizedPromptsStayInTheirLanguage() throws {
        let resources = SetupWizardFixture.root()
        let english = try SpriteSheetPrompt.load(
            for: CaptureHarness.localized(.english), resourcesAt: resources, style: .paperCutout
        )
        let japanese = try SpriteSheetPrompt.load(
            for: CaptureHarness.localized(.japanese), resourcesAt: resources, style: .paperCutout
        )
        #expect(english != japanese)
        #expect(english.localizedCaseInsensitiveContains("transparent"))
        #expect(japanese.contains("透明"))
        #expect(!english.contains("透明"))
        #expect(!japanese.localizedCaseInsensitiveContains("transparent"))
    }

    // MARK: - Fixtures

    private func block(_ path: String, in root: URL, kind: String = "text") throws -> String {
        let markdown = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        let marker = "```\(kind)\n"
        guard let start = markdown.range(of: marker),
              let end = markdown[start.upperBound...].range(of: "\n```")
        else {
            throw FixtureError.missingTextBlock
        }
        return String(markdown[start.upperBound ..< end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func markdown(_ body: String) -> String {
        "# Prompt\n\n```text\n\(body)\n```\n```character\nDEFAULT\n```\n"
    }

    private func makeResources(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaddlyTests.prompt.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("prompts"), withIntermediateDirectories: true
        )
        for (name, contents) in files {
            try contents.write(
                to: root.appendingPathComponent("prompts/\(name)"), atomically: true, encoding: .utf8
            )
        }
        return root
    }

    private enum FixtureError: Error {
        case missingTextBlock
    }
}
