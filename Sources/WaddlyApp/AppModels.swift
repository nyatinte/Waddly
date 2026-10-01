import Foundation
import WaddlyCore

enum AppLanguage: Int, CaseIterable {
    case system
    case japanese
    case english

    static let defaultsKey = "appLanguage"

    static var selected: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? .system
    }

    static let active = selected

    var localization: String {
        switch self {
        case .system: Self.detectedLocalization(Bundle.main.preferredLocalizations)
        case .japanese: "ja"
        case .english: "en"
        }
    }

    var titleKey: String {
        switch self {
        case .system: "language.system"
        case .japanese: "language.japanese"
        case .english: "language.english"
        }
    }

    static func detectedLocalization(_ preferredLocalizations: [String]) -> String {
        preferredLocalizations.first?.hasPrefix("ja") == true ? "ja" : "en"
    }
}

func localizedString(_ key: String) -> String {
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
        case .off: localizedString("motion.off")
        case .weak: localizedString("motion.weak")
        case .strong: localizedString("motion.strong")
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
        localizedString("images.category.\(rawValue)")
    }
}

func moving<Element>(_ elements: [Element], from source: Int, to destination: Int) -> [Element]? {
    guard elements.indices.contains(source), elements.indices.contains(destination) else { return nil }
    var result = elements
    let item = result.remove(at: source)
    result.insert(item, at: destination)
    return result
}
