import Foundation
import WaddlyCore

enum AppLanguage: Int, CaseIterable {
    case system
    case japanese
    case english

    var localization: String {
        switch self {
        case .system: Self.detectedLocalization(Bundle.main.preferredLocalizations)
        case .japanese: "ja"
        case .english: "en"
        }
    }

    var titleKey: LocalizationKey {
        switch self {
        case .system: .languageSystem
        case .japanese: .languageJapanese
        case .english: .languageEnglish
        }
    }

    static func detectedLocalization(_ preferredLocalizations: [String]) -> String {
        preferredLocalizations.first?.hasPrefix("ja") == true ? "ja" : "en"
    }
}

final class LocalizationController: Sendable {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var selectedLanguage: AppLanguage {
        settings.appLanguage
    }

    var activeLocalization: String {
        selectedLanguage.localization
    }

    func changeLanguage(_ language: AppLanguage) {
        settings.appLanguage = language
    }

    func string(for key: LocalizationKey) -> String {
        let key = key.rawValue
        guard let path = Bundle.main.path(forResource: activeLocalization, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

enum PetPhase: Equatable {
    case typing
    case idle
    case sleeping
    case frozen

    static func after(_ seconds: TimeInterval) -> PetPhase {
        let elapsed = max(0, seconds)
        if elapsed < 2.5 {
            return .typing
        }
        if elapsed < 25 {
            return .idle
        }
        if elapsed < 325 {
            return .sleeping
        }
        return .frozen
    }
}

enum TypingMotion: Int, CaseIterable {
    case off
    case weak
    case strong

    func title(using localization: LocalizationController) -> String {
        switch self {
        case .off: localization.string(for: .motionOff)
        case .weak: localization.string(for: .motionWeak)
        case .strong: localization.string(for: .motionStrong)
        }
    }

    var amplitude: CGFloat {
        switch self {
        case .off: 0
        case .weak: 5
        case .strong: 10
        }
    }
}

extension PetImageCategory {
    func title(using localization: LocalizationController) -> String {
        switch self {
        case .idle: localization.string(for: .imagesCategoryIdle)
        case .typing: localization.string(for: .imagesCategoryTyping)
        case .enter: localization.string(for: .imagesCategoryEnter)
        case .sleep: localization.string(for: .imagesCategorySleep)
        }
    }
}

func moving<Element>(_ elements: [Element], from source: Int, to destination: Int) -> [Element]? {
    guard elements.indices.contains(source), elements.indices.contains(destination) else { return nil }
    var result = elements
    let item = result.remove(at: source)
    result.insert(item, at: destination)
    return result
}
