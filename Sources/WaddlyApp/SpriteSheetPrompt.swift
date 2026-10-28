import AppKit

/// Composes and copies the externally generated sprite-sheet prompt.
///
/// One shared contract (`prompts/<language>.md`) describes the 3×3 sheet every style must produce;
/// one short style block (`prompts/<style>-<language>.md`) describes only the rendering style. The
/// two are joined here so the nine-pose specification can never drift between styles.
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

    /// The shared contract (with the character line filled in) followed by the selected style.
    ///
    /// The contract carries exactly one `{{character}}` placeholder and one `character` block that
    /// supplies the default line. A missing or ambiguous resource fails closed, so the copy action
    /// reports `.unavailable` instead of putting a half prompt on the clipboard.
    static func load(
        for localization: LocalizationController,
        resourcesAt resourceURL: URL?,
        style: CharacterStyle = .pixelArt,
        character: String = ""
    ) -> String {
        guard let resourceURL else { return "" }
        let language = localization.activeLocalization
        let contractURL = resourceURL.appendingPathComponent("prompts/\(language).md")
        let styleURL = resourceURL.appendingPathComponent("prompts/\(style.rawValue)-\(language).md")
        guard let template = textBlock(at: contractURL),
              let defaultCharacter = textBlock(in: contractURL, kind: "character"),
              let styleGuidance = textBlock(at: styleURL)
        else {
            return ""
        }
        let parts = template.components(separatedBy: "{{character}}")
        guard parts.count == 2 else { return "" }
        let described = character.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = described.isEmpty ? defaultCharacter : described
        return parts[0] + line + parts[1] + "\n\n" + styleGuidance
    }

    /// Reads the single fenced `text` block a prompt resource is allowed to carry.
    ///
    /// A second marker makes the block ambiguous, so it fails closed rather than silently cutting a
    /// document in half at the wrong fence.
    private static func textBlock(at url: URL) -> String? {
        textBlock(in: url, kind: "text")
    }

    private static func textBlock(in url: URL, kind: String) -> String? {
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return block(in: markdown, kind: kind)
    }

    private static func block(in markdown: String, kind: String) -> String? {
        let marker = "```\(kind)\n"
        guard let start = markdown.range(of: marker),
              let end = markdown[start.upperBound...].range(of: "\n```"),
              markdown.range(of: marker, range: start.upperBound ..< markdown.endIndex) == nil
        else {
            return nil
        }
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
