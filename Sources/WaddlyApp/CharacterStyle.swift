import Foundation

/// The curated visual styles offered when generating a character sheet.
///
/// The raw value is the resource slug for the style's guidance: adding a style is one case plus the
/// `prompts/<rawValue>-<language>.md` resources. Nothing else switches on the case list, and no style
/// rule lives in code.
enum CharacterStyle: String, CaseIterable, Identifiable {
    case pixelArt = "pixel-art"
    case handDrawn = "hand-drawn"
    case iconic
    case retroCartoon = "retro-cartoon"
    case anime
    case paperCutout = "paper-cutout"

    var id: String {
        rawValue
    }

    /// The localized display name. Kept beside the enum so the list, the prompt resources, and the
    /// sample sheets cannot disagree about which styles exist.
    var nameKey: LocalizationKey {
        switch self {
        case .pixelArt: .characterStylePixelArt
        case .handDrawn: .characterStyleHandDrawn
        case .iconic: .characterStyleIconic
        case .retroCartoon: .characterStyleRetroCartoon
        case .anime: .characterStyleAnime
        case .paperCutout: .characterStylePaperCutout
        }
    }
}
