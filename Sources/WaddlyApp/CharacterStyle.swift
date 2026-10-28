import Foundation

/// The curated visual styles offered when generating a character sheet.
///
/// The raw value is the resource slug, so adding a style is one case plus its two resources:
/// `prompts/<rawValue>-<language>.md` carries the style guidance that is appended to the shared
/// contract, and `assets/character-styles/<rawValue>.png` is the reference sheet shown in the
/// chooser. Nothing else switches on the case list, and no style rule lives in code.
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
}
