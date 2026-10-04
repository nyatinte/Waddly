import Foundation
import WaddlyCore

enum AppLanguage: Int, CaseIterable {
    case system
    case japanese
    case english

    static var selected: AppLanguage {
        AppSettings.standard.appLanguage
    }

    static var active: AppLanguage {
        selected
    }

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

func localizedString(_ key: LocalizationKey) -> String {
    let key = key.rawValue
    let localization = AppLanguage.active.localization
    guard let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else {
        return NSLocalizedString(key, comment: "")
    }
    return NSLocalizedString(key, bundle: bundle, comment: "")
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

    var title: String {
        switch self {
        case .off: localizedString(.motionOff)
        case .weak: localizedString(.motionWeak)
        case .strong: localizedString(.motionStrong)
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
    var title: String {
        switch self {
        case .idle: localizedString(.imagesCategoryIdle)
        case .typing: localizedString(.imagesCategoryTyping)
        case .enter: localizedString(.imagesCategoryEnter)
        case .sleep: localizedString(.imagesCategorySleep)
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
