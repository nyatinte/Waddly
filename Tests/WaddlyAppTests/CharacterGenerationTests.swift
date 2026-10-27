import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct CharacterGenerationTests {
    @Test(arguments: [AppLanguage.english, .japanese])
    func draftDefaultsToPixelArtWithTheDefaultCharacter(language: AppLanguage) throws {
        let draft = CharacterGenerationDraft()
        let localization = try CaptureHarness.localized(language)
        let resources = SetupWizardFixture.root()
        #expect(draft.style == .pixelArt)
        #expect(draft.description.isEmpty)
        let prompt = draft.prompt(for: localization, resourcesAt: resources)
        #expect(!prompt.isEmpty)
        #expect(prompt == SpriteSheetPrompt.load(for: localization, resourcesAt: resources))
        #expect(draft.prompt(for: localization, resourcesAt: nil).isEmpty)
    }

    @Test(arguments: [AppLanguage.english, .japanese])
    func changingEveryStylePreservesTheLiteralDescription(language: AppLanguage) throws {
        let draft = CharacterGenerationDraft()
        let description = "  A penguin {{character}} $1\nwith a red scarf.  \n"
        draft.description = description
        let localization = try CaptureHarness.localized(language)
        let resources = SetupWizardFixture.root()
        var prompts: Set<String> = []
        for style in CharacterGenerationStyle.allCases {
            draft.style = style
            let prompt = draft.prompt(for: localization, resourcesAt: resources)
            #expect(draft.description == description)
            #expect(prompt.contains(description))
            #expect(prompt == SpriteSheetPrompt.load(
                for: localization, resourcesAt: resources, style: style, description: description
            ))
            prompts.insert(prompt)
        }
        #expect(prompts.count == 6)
    }

    @Test(arguments: [false, true])
    func cardCopiesTheInjectedDraftInTheCurrentLanguageWithoutImageMutation(openChatGPT: Bool) async throws {
        let stored = try SetupWizardFixture.sheetImages()
        var commits = 0
        let model = CharacterImportModel(currentImages: { stored }, commit: { _ in
            commits += 1
            return .committed
        })
        defer { model.discard() }
        try await model.stageFiles(at: [SetupWizardFixture.sheetURL()])
        let staged = try #require(model.stagedFrames)
        try #require(model.isDirty)
        let draft = CharacterGenerationDraft()
        draft.description = "A small penguin in a red scarf"
        let localization = try CaptureHarness.localized(.english)
        let pasteboard = try CaptureHarness.pasteboard(holdsSheet: true)
        defer { pasteboard.releaseGlobally() }
        model.refreshClipboardAvailability(from: pasteboard)
        try #require(model.clipboardHasImage)
        var opened: [URL] = []
        var announcements: [String] = []
        let card = CharacterPromptCard(
            localization: localization, pasteboard: pasteboard,
            onClipboardChange: { model.refreshClipboardAvailability(from: pasteboard) },
            resourcesURL: SetupWizardFixture.root(), openBrowser: { url in
                #expect(pasteboard.string(forType: .string)?.contains(draft.description) == true)
                opened.append(url)
                return true
            }, announce: { announcements.append($0) }, draft: draft
        )
        for language in [AppLanguage.english, .japanese] {
            localization.changeLanguage(language)
            draft.style = language == .english ? .anime : .paperCutout
            #expect(card.copy(openChatGPT: openChatGPT) == .copied)
            #expect(pasteboard.string(forType: .string) == SpriteSheetPrompt.load(
                for: localization, resourcesAt: SetupWizardFixture.root(),
                style: draft.style, description: draft.description
            ))
            #expect(announcements.last == localization.string(for: .setupPromptCopied))
        }
        let chatGPT = try #require(URL(string: "https://chatgpt.com/"))
        #expect(opened == (openChatGPT ? [chatGPT, chatGPT] : []))
        #expect(!model.clipboardHasImage)
        #expect(model.isDirty)
        #expect(try CharacterImportModel.sameFrames(#require(model.stagedFrames), staged))
        #expect(CharacterImportModel.sameFrames(model.committedBaseline, stored))
        #expect(commits == 0)
    }

    @Test func setupRetainsItsDraftThroughNavigationAndCopiesItsCurrentPrompt() throws {
        let state = SetupWizardFixture.State()
        state.images = try SetupWizardFixture.sheetImages()
        let wizard = try SetupWizardFixture.makeWizard(language: .english, state: state, granted: true)
        defer {
            wizard.close()
            wizard.pasteboard.releaseGlobally()
        }
        let draft = wizard.generationDraft
        draft.style = .retroCartoon
        draft.description = "A penguin with a striped scarf"
        wizard.showChatGPTGuide()
        wizard.changeMethod()
        wizard.beginCharacterImport()
        #expect(wizard.isComposingCharacter)
        wizard.cancelCharacterImport()
        #expect(!wizard.isComposingCharacter)
        wizard.goNext()
        #expect(wizard.currentStep == .monitoring)
        wizard.goNext()
        #expect(wizard.currentStep == .completed)
        wizard.goBack()
        #expect(wizard.currentStep == .monitoring)
        wizard.goBack()
        #expect(wizard.currentStep == .pet)
        wizard.showChatGPTGuide()
        #expect(wizard.generationDraft === draft)
        #expect(draft.style == .retroCartoon)
        #expect(draft.description == "A penguin with a striped scarf")
        var prompts: Set<String> = []
        for language in [AppLanguage.english, .japanese] {
            wizard.localization.changeLanguage(language)
            let expected = SpriteSheetPrompt.load(
                for: wizard.localization, resourcesAt: SetupWizardFixture.root(),
                style: .retroCartoon, description: draft.description
            )
            #expect(!expected.isEmpty)
            #expect(wizard.prompt == expected)
            wizard.copyPromptAndOpenChatGPT()
            #expect(wizard.pasteboard.string(forType: .string) == expected)
            #expect(wizard.promptFeedback == .copied)
            prompts.insert(expected)
        }
        #expect(prompts.count == 2)
        #expect(state.commitCharacterCount == 0)
        #expect(state.confirmCount == 0)
    }
}

@Suite(.serialized) @MainActor struct CharacterStylePreviewTests {
    @Test func previewLoadsAllSixShippedSamplesAsStaticIdleFrames() throws {
        let preview = CharacterStylePreview(resourcesAt: SetupWizardFixture.root())
        #expect(preview.samples.count == 6)
        #expect(preview.playingStyle == nil)
        #expect(preview.image == nil)
        for style in CharacterGenerationStyle.allCases {
            let images = try #require(preview.samples[style])
            #expect(images.isComplete)
            #expect(images.isWithinMemoryBudget)
            #expect(PetImageCategory.allCases.map { images[$0].count } == [2, 4, 2, 1])
            #expect(preview.frame(for: style) === images[.idle].first)
            let url = SetupWizardFixture.root()
                .appendingPathComponent("assets/character-styles/\(style.rawValue).png")
            let expected = try PetSpriteSheetImporter.inspectFile(at: url).get().images
            let idle = try #require(images[.idle].first)
            let expectedIdle = try #require(expected[.idle].first)
            #expect(try #require(idle.tiffRepresentation) == #require(expectedIdle.tiffRepresentation))
        }
    }

    @Test(arguments: CharacterGenerationStyle.allCases, PetImageCategory.allCases)
    func previewPlaysOneFiniteSemanticCategoryInOrder(
        style: CharacterGenerationStyle, category: PetImageCategory
    ) async throws {
        let gate = GenerationSleepGate()
        let preview = CharacterStylePreview(resourcesAt: SetupWizardFixture.root(), sleep: gate.sleep)
        defer {
            preview.stop()
            gate.resumeAll()
        }
        let images = try #require(preview.samples[style])
        let frames = images[category]
        let durations: [TimeInterval] = switch category {
        case .idle: [1.5, 0.5]
        case .typing: [0.32, 0.32, 0.32, 0.32]
        case .enter: [1.1]
        case .sleep: [1.2, 1.6]
        }
        try #require(frames.count == durations.count)
        preview.play(style, category: category, reduceMotion: false)
        #expect(preview.frame(for: style) === frames.first)
        for (index, seconds) in durations.enumerated() {
            await yieldUntil { gate.durations.count == index + 1 }
            try #require(gate.durations.count == index + 1)
            #expect(gate.durations[index] == seconds)
            #expect(seconds.isFinite && seconds > 0)
            #expect(preview.playingStyle == style)
            #expect(preview.image === frames[index])
            #expect(preview.frame(for: style) === frames[index])
            gate.resumeNext()
        }
        await yieldUntil { preview.playingStyle == nil }
        #expect(preview.playingStyle == nil)
        #expect(preview.image == nil)
        #expect(preview.frame(for: style) === images[.idle].first)
        #expect(gate.durations == durations)
    }

    @Test func playbackIsExclusiveAndAnUnrelatedStopCannotCancelTheActiveStyle() async throws {
        let gate = GenerationSleepGate()
        let preview = CharacterStylePreview(resourcesAt: SetupWizardFixture.root(), sleep: gate.sleep)
        defer {
            preview.stop()
            gate.resumeAll()
        }
        let pixel = try #require(preview.samples[.pixelArt])
        let anime = try #require(preview.samples[.anime])
        preview.play(.pixelArt, category: .typing, reduceMotion: false)
        await yieldUntil { gate.durations.count == 1 }
        try #require(gate.durations.count == 1)
        preview.stop(.anime)
        #expect(preview.playingStyle == .pixelArt)
        #expect(preview.image === pixel[.typing].first)
        preview.play(.anime, category: .sleep, reduceMotion: false)
        #expect(preview.playingStyle == .anime)
        #expect(preview.frame(for: .pixelArt) === pixel[.idle].first)
        #expect(preview.frame(for: .anime) === anime[.sleep].first)
        await yieldUntil { gate.durations.count == 2 }
        try #require(gate.durations.count == 2)
        // Resume the cancelled task while the replacement remains suspended.
        gate.resumeNext()
        await yieldUntil { gate.resumedCount == 1 }
        #expect(gate.resumedCount == 1)
        preview.stop(.pixelArt)
        #expect(preview.playingStyle == .anime)
        #expect(preview.image === anime[.sleep].first)
        #expect(gate.durations == [0.32, 1.2])
        preview.stop(.anime)
        #expect(preview.playingStyle == nil)
        #expect(preview.image == nil)
        gate.resumeAll()
        await yieldUntil { gate.resumedCount == 2 }
        #expect(gate.resumedCount == 2)
        #expect(gate.durations == [0.32, 1.2])
        #expect(preview.playingStyle == nil)
        #expect(preview.frame(for: .anime) === anime[.idle].first)
    }

    @Test func leavingAutomaticPreviewDoesNotCancelAnExplicitPreview() {
        let preview = CharacterStylePreview(resourcesAt: SetupWizardFixture.root())
        defer { preview.stop() }
        preview.play(.anime, category: .enter, reduceMotion: false)
        preview.stop(.anime, trigger: .focus)
        preview.stop(.anime, trigger: .hover)
        preview.play(.pixelArt, reduceMotion: false, trigger: .hover)
        preview.play(.pixelArt, reduceMotion: false, trigger: .focus)
        #expect(preview.playingStyle == .anime)
        preview.stop()
        preview.play(.anime, reduceMotion: false, trigger: .focus)
        preview.stop(.anime, trigger: .focus)
        #expect(preview.playingStyle == nil)
        preview.play(.anime, reduceMotion: false, trigger: .hover)
        preview.stop(.anime, trigger: .hover)
        #expect(preview.playingStyle == nil)
    }

    @Test func reducedMotionStopsPlaybackAndKeepsEveryStyleStatic() async throws {
        let gate = GenerationSleepGate()
        let preview = CharacterStylePreview(resourcesAt: SetupWizardFixture.root(), sleep: gate.sleep)
        defer {
            preview.stop()
            gate.resumeAll()
        }
        preview.play(.pixelArt, category: .typing, reduceMotion: false)
        await yieldUntil { gate.durations.count == 1 }
        try #require(gate.durations.count == 1)
        for style in CharacterGenerationStyle.allCases {
            let idle = try #require(preview.samples[style]?[.idle].first)
            preview.play(style, category: .sleep, reduceMotion: true)
            #expect(preview.playingStyle == nil)
            #expect(preview.image == nil)
            #expect(preview.frame(for: style) === idle)
        }
        gate.resumeAll()
        await yieldUntil { gate.resumedCount == 1 }
        #expect(gate.resumedCount == 1)
        #expect(gate.durations == [0.32])
        #expect(preview.playingStyle == nil)
        #expect(preview.image == nil)
    }

    @Test(arguments: [false, true])
    func missingSampleResourcesNeverStartPlayback(hasResourceRoot: Bool) async {
        let resources = hasResourceRoot
            ? SetupWizardFixture.root().appendingPathComponent("missing-\(UUID().uuidString)") : nil
        var sleeps = 0
        let preview = CharacterStylePreview(resourcesAt: resources, sleep: { _ in sleeps += 1 })
        defer { preview.stop() }
        #expect(preview.samples.isEmpty)
        for style in CharacterGenerationStyle.allCases {
            #expect(preview.frame(for: style) == nil)
            preview.play(style, category: .typing, reduceMotion: false)
            #expect(preview.playingStyle == nil)
            #expect(preview.image == nil)
            preview.stop(style)
        }
        for _ in 0 ..< 200 {
            await Task.yield()
        }
        #expect(sleeps == 0)
        #expect(preview.playingStyle == nil)
        #expect(preview.image == nil)
    }

    private func yieldUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            await Task.yield()
        }
    }
}

@MainActor private final class GenerationSleepGate {
    private(set) var durations: [TimeInterval] = []
    private(set) var resumedCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(_ seconds: TimeInterval) async {
        durations.append(seconds)
        await withCheckedContinuation { continuations.append($0) }
        resumedCount += 1
    }

    func resumeNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
