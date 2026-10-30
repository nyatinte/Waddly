import AppKit

/// The bundled prompt and the two hand-offs to an image generator, shared by setup and character
/// management. The link carries the prompt, so the usual path needs no clipboard round trip.
enum SpriteSheetPrompt {
    enum Feedback: Equatable {
        /// ChatGPT was opened with the prompt already in its composer.
        case opened
        /// The clipboard-only hand-off for another generator. Change Character still offers it.
        case copied
        /// The browser could not be opened, so the prompt is on the clipboard for a manual paste.
        case copiedAfterOpenFailed
        case copyFailed
        case unavailable

        var messageKey: LocalizationKey {
            switch self {
            case .opened: .setupChatGPTOpened
            case .copied: .setupPromptCopied
            case .copiedAfterOpenFailed: .setupOpenFailed
            case .copyFailed: .setupCopyFailed
            case .unavailable: .characterPromptUnavailable
            }
        }

        var isError: Bool {
            switch self {
            case .opened, .copied: false
            case .copiedAfterOpenFailed, .copyFailed, .unavailable: true
            }
        }
    }

    static func load(for localization: LocalizationController, resourcesAt resourceURL: URL?) -> String {
        guard let url = resourceURL?.appendingPathComponent("prompts/\(localization.activeLocalization).md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8),
              let start = markdown.range(of: "```text\n"),
              let end = markdown[start.upperBound...].range(of: "```")
        else {
            return ""
        }
        return String(markdown[start.upperBound ..< end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// ChatGPT copies the `q` parameter into its composer, so the prompt travels in the link instead
    /// of the pasteboard. `URLComponents` percent-encodes the whole prompt, which matters because the
    /// bundled prompts carry quotes and, in Japanese, non-ASCII text.
    static func chatGPTURL(for prompt: String) -> URL? {
        guard var components = URLComponents(string: "https://chatgpt.com/") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: prompt)]
        return components.url
    }

    /// Opens ChatGPT with the prompt already written into its composer. When the browser cannot be
    /// opened the prompt goes to the clipboard instead, so a failed hand-off still leaves the user
    /// with something to paste rather than an empty browser tab.
    @MainActor
    static func open(
        _ prompt: String,
        to pasteboard: NSPasteboard,
        openBrowser: @MainActor (URL) -> Bool
    ) -> Feedback {
        guard !prompt.isEmpty else { return .unavailable }
        guard let url = chatGPTURL(for: prompt) else { return .copyFailed }
        guard openBrowser(url) else {
            return copy(prompt, to: pasteboard) == .copied ? .copiedAfterOpenFailed : .copyFailed
        }
        return .opened
    }

    /// A missing prompt must not erase the user's clipboard.
    @MainActor
    static func copy(_ prompt: String, to pasteboard: NSPasteboard) -> Feedback {
        guard !prompt.isEmpty else { return .unavailable }
        pasteboard.clearContents()
        return pasteboard.setString(prompt, forType: .string) ? .copied : .copyFailed
    }
}
