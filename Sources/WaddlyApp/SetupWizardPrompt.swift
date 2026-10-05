import Foundation

extension SetupWizardController {
    static func loadPrompt(for localization: LocalizationController, resourcesAt resourceURL: URL?) -> String {
        guard let url = resourceURL?.appendingPathComponent("prompts/\(localization.activeLocalization).md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8),
              let start = markdown.range(of: "```text\n"),
              let end = markdown[start.upperBound...].range(of: "```")
        else {
            return ""
        }
        return String(markdown[start.upperBound ..< end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
