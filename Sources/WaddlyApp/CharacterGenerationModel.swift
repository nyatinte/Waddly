import AppKit
import WaddlyCore

/// How the person wants to brief the external generator. Every mode produces the same shared 3×3
/// contract; this only changes the guidance shown on the generation screen.
enum CharacterGenerationInput: String, CaseIterable, Identifiable {
    case text
    case referenceImage
    case imageAndText

    var id: String {
        rawValue
    }

    var titleKey: LocalizationKey {
        switch self {
        case .text: .characterGenerationFromText
        case .referenceImage: .characterGenerationFromReference
        case .imageAndText: .characterGenerationFromImageText
        }
    }

    var detailKey: LocalizationKey {
        switch self {
        case .text: .characterGenerationFromTextDetail
        case .referenceImage: .characterGenerationFromReferenceDetail
        case .imageAndText: .characterGenerationFromImageTextDetail
        }
    }

    var symbol: String {
        switch self {
        case .text: "square.and.pencil"
        case .referenceImage: "photo"
        case .imageAndText: "photo.badge.plus"
        }
    }
}

/// The generation choices have their own screen, so nothing here can stage, edit, or apply a pet.
/// The prompt is composed from the shared contract and one style block; the description only fills
/// the character line that contract already asks for.
@MainActor
final class CharacterGenerationModel: ObservableObject {
    /// Which sample is animating. Hovering a card animates that card; hovering the large preview
    /// animates the selected style. The pointer can only be over one of them, so one playback engine
    /// is enough.
    enum PlaybackTarget: Equatable {
        case card(CharacterStyle)
        case preview

        var style: CharacterStyle? {
            guard case let .card(style) = self else { return nil }
            return style
        }
    }

    /// One showcase pass: idle, blink, focused, typing, typing variation, fast typing, Enter, idle.
    /// The timings feel like a small desktop pet rather than a frame-by-frame animation.
    static let showcase: [(frame: Int, seconds: TimeInterval)] = [
        (0, 1.0), (1, 0.35), (0, 0.6), (2, 0.35), (3, 0.28), (4, 0.28), (5, 0.28), (6, 0.9), (0, 0.7)
    ]

    static let characterLimit = 500
    private static let sampleSheetPath = "assets/character-styles"

    let localization: LocalizationController
    private let resourcesURL: URL?
    private let pasteboard: NSPasteboard
    private let openBrowser: @MainActor (URL) -> Bool
    private let announce: @MainActor (String) -> Void
    private let onClipboardChange: @MainActor () -> Void
    /// Injectable so tests can drive playback without waiting on wall-clock time.
    private let sleep: @MainActor (TimeInterval) async -> Void

    @Published var style = CharacterStyle.pixelArt {
        didSet {
            stopPlayback()
            feedback = nil
            previewIndex = 0
        }
    }

    @Published var character = "" {
        didSet {
            clampCharacter()
            feedback = nil
        }
    }

    @Published var input = CharacterGenerationInput.text {
        didSet { feedback = nil }
    }

    /// Which of the nine sample cells the large preview shows. It never changes the prompt or any
    /// saved state.
    @Published var previewIndex = 0
    @Published private(set) var feedback: SpriteSheetPrompt.Feedback?
    @Published private(set) var sampleFrames: [CharacterStyle: [NSImage]] = [:]
    @Published private(set) var playingTarget: PlaybackTarget?
    @Published private(set) var playingFrame: NSImage?
    private var promptCache: PromptCache?
    private var didLoadSamples = false
    private var playbackTask: Task<Void, Never>?
    private var playbackGeneration = 0

    init(
        localization: LocalizationController,
        resourcesURL: URL?,
        pasteboard: NSPasteboard,
        openBrowser: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        announce: @escaping @MainActor (String) -> Void = SetupWizardController.postAccessibilityAnnouncement,
        onClipboardChange: @escaping @MainActor () -> Void = {},
        sleep: @escaping @MainActor (TimeInterval) async -> Void = CharacterGenerationModel.defaultSleep
    ) {
        self.localization = localization
        self.resourcesURL = resourcesURL
        self.pasteboard = pasteboard
        self.openBrowser = openBrowser
        self.announce = announce
        self.onClipboardChange = onClipboardChange
        self.sleep = sleep
    }

    static func defaultSleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// The composed prompt, cached until the style, the description, or the app language changes.
    /// A SwiftUI body reads this several times per render, so re-reading and parsing both markdown
    /// resources every time would be wasteful.
    var prompt: String {
        if let cached = cachedPrompt(language: localization.activeLocalization) {
            return cached
        }
        let language = localization.activeLocalization
        let text = SpriteSheetPrompt.load(
            for: localization,
            resourcesAt: resourcesURL,
            style: style,
            character: character
        )
        promptCache = PromptCache(style: style, character: character, language: language, text: text)
        return text
    }

    /// A cache hit needs every input that can change the composed text.
    private func cachedPrompt(language: String) -> String? {
        guard let promptCache,
              promptCache.style == style,
              promptCache.character == character,
              promptCache.language == language
        else {
            return nil
        }
        return promptCache.text
    }

    var characterCount: Int {
        character.count
    }

    var feedbackKey: LocalizationKey? {
        feedback?.messageKey
    }

    var feedbackIsError: Bool {
        feedback?.isError == true
    }

    var currentFrames: [NSImage] {
        sampleFrames[style] ?? []
    }

    /// The frame a style card shows: its animated frame while that card is hovered, otherwise the
    /// idle cell.
    func image(for style: CharacterStyle) -> NSImage? {
        if playingTarget == .card(style), let playingFrame {
            return playingFrame
        }
        return sampleFrames[style]?.first
    }

    /// The frame the large preview shows. Playback wins while the preview is hovered; otherwise the
    /// strip selection does, falling back to the idle cell when that index no longer fits.
    var previewFrame: NSImage? {
        if playingTarget == .preview, let playingFrame {
            return playingFrame
        }
        let frames = currentFrames
        guard frames.indices.contains(previewIndex) else { return frames.first }
        return frames[previewIndex]
    }

    var isPlaying: Bool {
        playingTarget != nil
    }

    func loadSamplesIfNeeded() {
        guard !didLoadSamples else { return }
        didLoadSamples = true
        guard let resourcesURL else { return }
        var loaded: [CharacterStyle: [NSImage]] = [:]
        for style in CharacterStyle.allCases {
            let url = resourcesURL
                .appendingPathComponent(Self.sampleSheetPath)
                .appendingPathComponent("\(style.rawValue).png")
            guard case let .success(candidate) = PetSpriteSheetImporter.inspectFile(at: url) else {
                continue
            }
            let frames = Self.orderedFrames(candidate.images)
            if frames.count == 9 {
                loaded[style] = frames
            }
        }
        sampleFrames = loaded
    }

    /// Re-renders after the app language changes. The prompt cache is language-keyed, so clearing it
    /// makes the next read compose the new language, and the published change refreshes every body.
    func refreshLocalization() {
        promptCache = nil
        objectWillChange.send()
    }

    /// Plays the showcase until `stopPlayback` (or another target) wins. Reduce Motion keeps the
    /// static sample: the screen already shows what the style looks like.
    func play(_ target: PlaybackTarget, reduceMotion: Bool) {
        guard !reduceMotion else { return }
        let style = target.style ?? style
        let frames = sampleFrames[style] ?? []
        guard frames.count == 9 else { return }
        stopPlayback()
        playbackGeneration += 1
        let token = playbackGeneration
        playingTarget = target
        playingFrame = frames[0]
        playbackTask = Task { @MainActor [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let self, token == playbackGeneration else { return }
                let shot = Self.showcase[index % Self.showcase.count]
                playingFrame = frames[shot.frame]
                await sleep(shot.seconds)
                guard !Task.isCancelled, token == playbackGeneration else { return }
                index += 1
            }
        }
    }

    /// Stops one target (used when a hover ends) without cancelling playback that has already moved
    /// to another target. With no argument, stops whatever is playing.
    func stopPlayback(_ target: PlaybackTarget? = nil) {
        if let target, playingTarget != target {
            return
        }
        playbackGeneration += 1
        playbackTask?.cancel()
        playbackTask = nil
        playingTarget = nil
        playingFrame = nil
    }

    func copyPrompt() {
        copy(openChatGPT: false)
    }

    func copyAndOpenChatGPT() {
        copy(openChatGPT: true)
    }

    private func copy(openChatGPT: Bool) {
        let result = SpriteSheetPrompt.copy(
            prompt,
            to: pasteboard,
            openBrowser: openChatGPT ? openBrowser : nil
        )
        onClipboardChange()
        feedback = result
        if result.isError {
            announce(localization.string(for: result.messageKey))
        }
    }

    /// Keeps the text view and the count in sync with the documented limit without truncating a
    /// paste repeatedly: the assignment fires `didSet` once more, where the guard already holds.
    private func clampCharacter() {
        guard character.count > Self.characterLimit else { return }
        character = String(character.prefix(Self.characterLimit))
    }

    /// The importer groups the nine cells by pose, not by sheet order; this puts them back into the
    /// canonical row-major order the preview strip documents.
    private static func orderedFrames(_ images: PetImageSet) -> [NSImage] {
        images[.idle] + images[.typing] + images[.enter] + images[.sleep]
    }

    private struct PromptCache {
        let style: CharacterStyle
        let character: String
        let language: String
        let text: String
    }
}
