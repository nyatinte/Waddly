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

    /// The shared contract followed by the selected style's guidance.
    ///
    /// Returns an empty string when either resource is missing or malformed; the copy action then
    /// reports `.unavailable` instead of putting a half prompt on the clipboard.
    static func load(
        for localization: LocalizationController,
        resourcesAt resourceURL: URL?,
        style: CharacterStyle = .pixelArt
    ) -> String {
        guard let resourceURL else { return "" }
        let language = localization.activeLocalization
        guard let contract = textBlock(at: resourceURL.appendingPathComponent("prompts/\(language).md")),
              let styleGuidance = textBlock(
                  at: resourceURL.appendingPathComponent("prompts/\(style.rawValue)-\(language).md")
              )
        else {
            return ""
        }
        return contract + "\n\n" + styleGuidance
    }

    /// Reads the single fenced `text` block a prompt resource is allowed to carry.
    ///
    /// A second marker makes the block ambiguous, so it fails closed rather than silently cutting a
    /// document in half at the wrong fence.
    private static func textBlock(at url: URL) -> String? {
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let marker = "```text\n"
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

extension SetupWizardController {
    static func loadPrompt(
        for localization: LocalizationController,
        resourcesAt resourceURL: URL?,
        style: CharacterStyle = .pixelArt
    ) -> String {
        SpriteSheetPrompt.load(for: localization, resourcesAt: resourceURL, style: style)
    }
}
