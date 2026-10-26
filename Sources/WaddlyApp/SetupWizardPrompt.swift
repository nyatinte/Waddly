import AppKit

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
    static func loadPrompt(for localization: LocalizationController, resourcesAt resourceURL: URL?) -> String {
        SpriteSheetPrompt.load(for: localization, resourcesAt: resourceURL)
    }
}
