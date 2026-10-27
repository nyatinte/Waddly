import AppKit

enum CharacterGenerationStyle: String, CaseIterable, Identifiable {
    case pixelArt = "pixel-art"
    case handDrawn = "hand-drawn"
    case iconic
    case retroCartoon = "retro-cartoon"
    case anime
    case paperCutout = "paper-cutout"

    var id: String {
        rawValue
    }
}

/// The bundled prompt and clipboard action are shared by setup and character management.
enum SpriteSheetPrompt {
    enum Feedback: Equatable {
        case copied
        case copyFailed
        case openFailed
        case unavailable

        var messageKey: LocalizationKey {
            switch self {
            case .copied: .setupPromptCopied
            case .copyFailed: .setupCopyFailed
            case .openFailed: .setupOpenFailed
            case .unavailable: .characterPromptUnavailable
            }
        }

        var isError: Bool {
            self != .copied
        }
    }

    static func load(
        for localization: LocalizationController,
        resourcesAt resourceURL: URL?,
        style: CharacterGenerationStyle = .pixelArt,
        description: String = ""
    ) -> String {
        let language = localization.activeLocalization
        guard let resourceURL,
              let markdown = try? String(
                  contentsOf: resourceURL.appendingPathComponent("prompts/\(language).md"), encoding: .utf8
              ),
              let common = fencedBlock(in: markdown, kind: "text"),
              let defaultCharacter = fencedBlock(in: markdown, kind: "character"),
              let styleMarkdown = try? String(
                  contentsOf: resourceURL.appendingPathComponent("prompts/\(style.rawValue)-\(language).md"),
                  encoding: .utf8
              ),
              let styleBlock = fencedBlock(in: styleMarkdown, kind: "text")
        else {
            return ""
        }
        let parts = common.components(separatedBy: "{{character}}")
        guard parts.count == 2 else { return "" }
        let character = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultCharacter : description
        // Split only the resource template; user text, including template markers, stays literal.
        return parts[0] + character + parts[1] + "\n\n" + styleBlock
    }

    private static func fencedBlock(in markdown: String, kind: String) -> String? {
        let marker = "```\(kind)\n"
        guard let start = markdown.range(of: marker),
              let end = markdown[start.upperBound...].range(of: "\n```"),
              markdown.range(of: marker, range: start.upperBound ..< markdown.endIndex) == nil
        else { return nil }
        let body = String(markdown[start.upperBound ..< end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    /// A missing prompt must not erase the user's clipboard or open a browser with nothing to paste.
    @MainActor
    static func copy(
        _ prompt: String,
        to pasteboard: NSPasteboard,
        openBrowser: (@MainActor (URL) -> Bool)? = nil
    ) -> Feedback {
        guard !prompt.isEmpty else { return .unavailable }
        pasteboard.clearContents()
        guard pasteboard.setString(prompt, forType: .string) else { return .copyFailed }
        guard let openBrowser, let url = URL(string: "https://chatgpt.com/") else { return .copied }
        return openBrowser(url) ? .copied : .openFailed
    }
}
