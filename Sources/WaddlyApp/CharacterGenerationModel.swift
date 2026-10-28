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
    static let characterLimit = 500
    private static let cameraSheetPath = "assets/character-styles"

    let localization: LocalizationController
    private let resourcesURL: URL?
    private let pasteboard: NSPasteboard
    private let openBrowser: @MainActor (URL) -> Bool
    private let announce: @MainActor (String) -> Void

    @Published var style = CharacterStyle.pixelArt {
        didSet {
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

    /// Which of the nine sample cells the preview shows. Purely inspection; it does not change the
    /// prompt or any saved state.
    @Published var previewIndex = 0
    @Published private(set) var feedback: SpriteSheetPrompt.Feedback?
    @Published private(set) var sampleFrames: [CharacterStyle: [NSImage]] = [:]
    private var didLoadSamples = false

    init(
        localization: LocalizationController,
        resourcesURL: URL?,
        pasteboard: NSPasteboard,
        openBrowser: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        announce: @escaping @MainActor (String) -> Void = SetupWizardController.postAccessibilityAnnouncement
    ) {
        self.localization = localization
        self.resourcesURL = resourcesURL
        self.pasteboard = pasteboard
        self.openBrowser = openBrowser
        self.announce = announce
    }

    var prompt: String {
        SpriteSheetPrompt.load(
            for: localization,
            resourcesAt: resourcesURL,
            style: style,
            character: character
        )
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

    /// The frame the large preview shows. Falls back to the idle cell when the stored index no
    /// longer fits, so a style whose samples failed to load still shows something coherent.
    var previewFrame: NSImage? {
        let frames = currentFrames
        guard frames.indices.contains(previewIndex) else { return frames.first }
        return frames[previewIndex]
    }

    func loadSamplesIfNeeded() {
        guard !didLoadSamples else { return }
        didLoadSamples = true
        guard let resourcesURL else { return }
        var loaded: [CharacterStyle: [NSImage]] = [:]
        for style in CharacterStyle.allCases {
            let url = resourcesURL
                .appendingPathComponent(Self.cameraSheetPath)
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
}
