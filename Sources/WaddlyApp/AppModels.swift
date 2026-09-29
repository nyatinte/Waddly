import Foundation
import WaddlyCore

func localizedString(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum PetPhase: Equatable {
    case typing
    case idle
    case sleeping
    case frozen

    static func after(_ seconds: TimeInterval) -> PetPhase {
        let elapsed = max(0, seconds)
        if elapsed < 2.5 { return .typing }
        if elapsed < 25 { return .idle }
        if elapsed < 325 { return .sleeping }
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
    var title: String { localizedString("images.category.\(rawValue)") }
}

func moving<Element>(_ elements: [Element], from source: Int, to destination: Int) -> [Element]? {
    guard elements.indices.contains(source), elements.indices.contains(destination) else { return nil }
    var result = elements
    let item = result.remove(at: source)
    result.insert(item, at: destination)
    return result
}
