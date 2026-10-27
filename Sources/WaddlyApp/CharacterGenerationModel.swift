import AppKit
import Combine
import WaddlyCore

/// Session-only generation choices never participate in the imported character's dirty state.
@MainActor
final class CharacterGenerationDraft: ObservableObject {
    @Published var style = CharacterGenerationStyle.pixelArt
    @Published var description = ""

    func prompt(for localization: LocalizationController, resourcesAt url: URL?) -> String {
        SpriteSheetPrompt.load(for: localization, resourcesAt: url, style: style, description: description)
    }
}

extension CharacterGenerationStyle {
    var nameKey: LocalizationKey {
        switch self {
        case .pixelArt: .generationStylePixelArt
        case .handDrawn: .generationStyleHandDrawn
        case .iconic: .generationStyleIconic
        case .retroCartoon: .generationStyleRetroCartoon
        case .anime: .generationStyleAnime
        case .paperCutout: .generationStylePaperCutout
        }
    }
}

/// One finite held-pose demonstration at a time, using the same crops and timings as pet previews.
@MainActor
final class CharacterStylePreview: ObservableObject {
    enum Trigger {
        case hover, focus, explicit
    }

    let samples: [CharacterGenerationStyle: PetImageSet]
    @Published private(set) var playingStyle: CharacterGenerationStyle?
    @Published private(set) var image: NSImage?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var trigger: Trigger?
    private let sleep: @MainActor (TimeInterval) async -> Void

    init(
        resourcesAt url: URL?,
        sleep: @escaping @MainActor (TimeInterval) async -> Void = PetPreviewPlayer.defaultSleep
    ) {
        self.sleep = sleep
        var loaded: [CharacterGenerationStyle: PetImageSet] = [:]
        if let url {
            for style in CharacterGenerationStyle.allCases {
                let sheet = url.appendingPathComponent("assets/character-styles/\(style.rawValue).png")
                if case let .success(candidate) = PetSpriteSheetImporter.inspectFile(at: sheet) {
                    loaded[style] = candidate.images
                }
            }
        }
        samples = loaded
    }

    func frame(for style: CharacterGenerationStyle) -> NSImage? {
        playingStyle == style ? image : samples[style]?[.idle].first
    }

    func play(
        _ style: CharacterGenerationStyle,
        category: PetImageCategory = .idle,
        reduceMotion: Bool,
        trigger: Trigger = .explicit
    ) {
        guard reduceMotion || trigger == .explicit || self.trigger != .explicit else { return }
        stop()
        guard !reduceMotion, let frames = samples[style] else { return }
        let shots = PetPreviewPlayer.shotSequence(for: category, in: frames)
        guard let first = shots.first else { return }
        playingStyle = style
        self.trigger = trigger
        image = first.image
        let token = generation
        task = Task { @MainActor [weak self] in
            for shot in shots {
                guard let self, !Task.isCancelled, token == generation else { return }
                image = shot.image
                await sleep(shot.seconds)
            }
            guard let self, !Task.isCancelled, token == generation else { return }
            stop()
        }
    }

    func stop(_ style: CharacterGenerationStyle? = nil, trigger: Trigger? = nil) {
        if let style, playingStyle != style {
            return
        }
        // Leaving a hover/focus must not cancel an explicit preview started by another control.
        if let trigger, self.trigger != trigger {
            return
        }
        generation += 1
        task?.cancel()
        task = nil
        playingStyle = nil
        self.trigger = nil
        image = nil
    }
}
