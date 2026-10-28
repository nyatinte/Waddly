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

    // MARK: - Fixtures

    private func model(
        localization: LocalizationController,
        resourcesURL: URL? = nil,
        pasteboard: NSPasteboard? = nil,
        openBrowser: @escaping @MainActor (URL) -> Bool = { _ in true },
        announce: @escaping @MainActor (String) -> Void = { _ in }
    ) throws -> CharacterGenerationModel {
        try CharacterGenerationModel(
            localization: localization,
            resourcesURL: resourcesURL ?? SetupWizardFixture.root(),
            pasteboard: pasteboard ?? namedPasteboard(),
            openBrowser: openBrowser,
            announce: announce
        )
    }

    private func namedPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("WaddlyTests.generation.\(UUID().uuidString)"))
    }
}
