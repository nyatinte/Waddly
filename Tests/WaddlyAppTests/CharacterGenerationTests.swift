import AppKit
import Testing
@testable import WaddlyApp

/// The generation screen is guidance only. These tests pin the composition (style + character),
/// the copy feedback, the sample previews, and the window wiring that setup and Change Character
/// share.
@Suite(.serialized) @MainActor struct CharacterGenerationTests {
    @Test func promptFollowsTheSelectedStyleAndDescription() throws {
        let localization = try CaptureHarness.localized(.english)
        let model = try model(localization: localization)
        let pixelArt = model.prompt
        #expect(pixelArt.contains("Pixel art"))
        #expect(pixelArt.contains("{{character}}") == false)

        model.style = .anime
        #expect(model.prompt.contains("[Art style]"))
        #expect(model.prompt != pixelArt)

        model.character = "A round blue penguin."
        #expect(model.prompt.contains("A round blue penguin."))
    }

    @Test func anEmptyDescriptionKeepsTheContractsOwnDefault() throws {
        let model = try model(localization: CaptureHarness.localized(.english))
        #expect(model.prompt.contains("<replace this line>"))
    }

    @Test func theDescriptionIsClampedToTheDocumentedLimit() throws {
        let model = try model(localization: CaptureHarness.localized(.english))
        model.character = String(repeating: "a", count: CharacterGenerationModel.characterLimit + 40)
        #expect(model.characterCount == CharacterGenerationModel.characterLimit)
        #expect(model.prompt.contains(String(repeating: "a", count: CharacterGenerationModel.characterLimit)))
    }

    @Test func copyActionsReportTheirResultAndOnlyAnnounceFailures() throws {
        let localization = try CaptureHarness.localized(.english)
        let pasteboard = namedPasteboard()
        defer { pasteboard.releaseGlobally() }
        var announcements: [String] = []
        var opened: [URL] = []
        let model = try model(
            localization: localization,
            pasteboard: pasteboard,
            openBrowser: { url in
                opened.append(url)
                return false
            },
            announce: { announcements.append($0) }
        )

        model.copyPrompt()
        #expect(model.feedback == .copied)
        #expect(pasteboard.string(forType: .string) == model.prompt)
        #expect(announcements.isEmpty)

        model.copyAndOpenChatGPT()
        #expect(try opened == [#require(URL(string: "https://chatgpt.com/"))])
        #expect(model.feedback == .openFailed)
        #expect(announcements == [localization.string(for: .setupOpenFailed)])
    }

    @Test func samplesLoadAsNineOrderedFramesForEveryStyle() throws {
        let model = try model(localization: CaptureHarness.localized(.english))
        model.loadSamplesIfNeeded()
        #expect(model.sampleFrames.count == CharacterStyle.allCases.count)
        for style in CharacterStyle.allCases {
            let frames = try #require(model.sampleFrames[style])
            #expect(frames.count == 9)
            #expect(frames.allSatisfy { $0.size.width > 0 })
        }
    }

    @Test func missingSamplesLeaveEveryStyleSelectable() throws {
        let model = try CharacterGenerationModel(
            localization: CaptureHarness.localized(.english),
            resourcesURL: nil,
            pasteboard: namedPasteboard()
        )
        model.loadSamplesIfNeeded()
        #expect(model.sampleFrames.isEmpty)
        #expect(model.previewFrame == nil)
        model.style = .paperCutout
        #expect(model.style == .paperCutout)
    }

    @Test func theWindowClosesOnceAndReportsIt() throws {
        let model = try model(localization: CaptureHarness.localized(.english))
        var closeCount = 0
        let controller = CharacterGenerationWindowController(model: model, presenter: .invisible) {
            closeCount += 1
        }
        controller.focus()
        #expect(controller.window?.title == model.localization.string(for: .characterGenerationTitle))
        controller.close()
        #expect(closeCount == 1)
    }

    @Test func setupPresentsOneGenerationWindowAndReusesIt() throws {
        var presented: [CharacterGenerationWindowController] = []
        let wizard = try SetupWizardFixture.makeWizard(presentGeneration: { presented.append($0) })
        defer { wizard.close() }

        wizard.presentCharacterGeneration()
        #expect(presented.count == 1)
        #expect(presented.first?.model.style == .pixelArt)

        wizard.presentCharacterGeneration()
        #expect(presented.count == 2)
        #expect(presented.first === presented.last)
    }

    @Test func hoverPlaybackAnimatesTheHoveredCardAndStops() throws {
        let model = try model(
            localization: CaptureHarness.localized(.english),
            sleep: { _ in }
        )
        model.loadSamplesIfNeeded()
        model.play(.card(.anime), reduceMotion: false)
        #expect(model.playingTarget == .card(.anime))
        #expect(model.image(for: .anime) === model.playingFrame)
        #expect(model.image(for: .pixelArt) === model.sampleFrames[.pixelArt]?.first)

        model.stopPlayback(.card(.anime))
        #expect(model.playingTarget == nil)
        #expect(model.image(for: .anime) === model.sampleFrames[.anime]?.first)
    }

    @Test func reduceMotionKeepsEverySampleStatic() throws {
        let model = try model(localization: CaptureHarness.localized(.english))
        model.loadSamplesIfNeeded()
        model.play(.card(.pixelArt), reduceMotion: true)
        #expect(model.playingTarget == nil)
        #expect(model.image(for: .pixelArt) === model.sampleFrames[.pixelArt]?.first)
    }

    @Test func previewPlaybackOutranksTheStripSelectionAndStops() throws {
        let model = try model(localization: CaptureHarness.localized(.english))
        model.loadSamplesIfNeeded()
        model.previewIndex = 4
        model.play(.preview, reduceMotion: false)
        #expect(model.playingTarget == .preview)
        #expect(model.previewFrame === model.playingFrame)

        model.stopPlayback(.preview)
        #expect(model.playingTarget == nil)
        #expect(model.previewFrame === model.sampleFrames[.pixelArt]?[4])
    }

    @Test func changingTheStyleStopsPlaybackFromTheOldStyle() throws {
        let model = try model(localization: CaptureHarness.localized(.english))
        model.loadSamplesIfNeeded()
        model.play(.preview, reduceMotion: false)
        model.style = .handDrawn
        #expect(model.playingTarget == nil)
        #expect(model.previewFrame === model.sampleFrames[.handDrawn]?[0])
    }

    @Test func localizationRefreshRepaintsWithTheNewLanguage() throws {
        let localization = try CaptureHarness.localized(.english)
        let model = try model(localization: localization)
        let english = model.prompt
        #expect(!english.isEmpty)

        localization.changeLanguage(.japanese)
        // The language is part of the cache key, so a copy reads Japanese immediately; the window's
        // refresh is what makes the visible screen (labels and prompt) repaint to match it.
        let japanese = model.prompt
        #expect(japanese != english)
        #expect(japanese.contains("透明"))

        model.refreshLocalization()
        #expect(model.prompt == japanese)
    }

    @Test func thePromptCacheIsInvalidatedByARealInputChange() throws {
        let resources = try makePromptResources()
        defer { try? FileManager.default.removeItem(at: resources) }
        let model = try model(
            localization: CaptureHarness.localized(.english),
            resourcesURL: resources
        )
        let first = model.prompt
        #expect(first == "Hello DEFAULT\n\n[Art style]\n- pixel")

        try FileManager.default.removeItem(
            at: resources.appendingPathComponent("prompts/pixel-art-en.md")
        )
        // A cache hit must not care that the file just disappeared.
        #expect(model.prompt == first)

        model.character = "A round penguin."
        #expect(model.prompt.isEmpty)
    }

    @Test func theWindowForwardsLocalizationRefreshToTheModel() throws {
        let localization = try CaptureHarness.localized(.english)
        let model = try model(localization: localization)
        let controller = CharacterGenerationWindowController(model: model, presenter: .invisible) {}
        defer { controller.close() }
        let english = model.prompt

        localization.changeLanguage(.japanese)
        controller.refreshLocalization()
        #expect(model.prompt != english)
        #expect(controller.window?.title == localization.string(for: .characterGenerationTitle))
    }

    @Test func copyingReportsTheClipboardChangeToItsHost() throws {
        var clipboardChanges = 0
        let model = try model(
            localization: CaptureHarness.localized(.english),
            onClipboardChange: { clipboardChanges += 1 }
        )
        model.copyPrompt()
        #expect(clipboardChanges == 1)
        model.copyAndOpenChatGPT()
        #expect(clipboardChanges == 2)
    }

    // MARK: - Fixtures

    private func model(
        localization: LocalizationController,
        resourcesURL: URL? = nil,
        pasteboard: NSPasteboard? = nil,
        openBrowser: @escaping @MainActor (URL) -> Bool = { _ in true },
        announce: @escaping @MainActor (String) -> Void = { _ in },
        onClipboardChange: @escaping @MainActor () -> Void = {},
        sleep: @escaping @MainActor (TimeInterval) async -> Void = CharacterGenerationModel.defaultSleep
    ) throws -> CharacterGenerationModel {
        try CharacterGenerationModel(
            localization: localization,
            resourcesURL: resourcesURL ?? SetupWizardFixture.root(),
            pasteboard: pasteboard ?? namedPasteboard(),
            openBrowser: openBrowser,
            announce: announce,
            onClipboardChange: onClipboardChange,
            sleep: sleep
        )
    }

    private func makePromptResources() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaddlyTests.generation.\(UUID().uuidString)", isDirectory: true)
        let prompts = root.appendingPathComponent("prompts", isDirectory: true)
        try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)
        try "```text\nHello {{character}}\n```\n```character\nDEFAULT\n```\n".write(
            to: prompts.appendingPathComponent("en.md"), atomically: true, encoding: .utf8
        )
        try "```text\n[Art style]\n- pixel\n```\n".write(
            to: prompts.appendingPathComponent("pixel-art-en.md"), atomically: true, encoding: .utf8
        )
        try "```text\n[Art style]\n- anime\n```\n".write(
            to: prompts.appendingPathComponent("anime-en.md"), atomically: true, encoding: .utf8
        )
        return root
    }

    private func namedPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("WaddlyTests.generation.\(UUID().uuidString)"))
    }
}
