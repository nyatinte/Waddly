import AppKit
import WaddlyCore

/// The result of reading one acquisition source.
enum CharacterSheetLoadOutcome: Sendable {
    case valid(PetSheetCandidate)
    /// The clipboard had nothing Waddly can import.
    case empty
    case invalid(PetSheetValidationFailure)
}

/// Decodes acquisition sources off the main thread. Pure: it never writes files or persistent state.
enum CharacterSheetLoader {
    static func load(from url: URL) async -> CharacterSheetLoadOutcome {
        await Task.detached(priority: .userInitiated) {
            guard let data = PetSpriteSheetImporter.readPNG(from: url) else { return .invalid(.unreadable) }
            return inspect(data)
        }.value
    }

    /// The pasteboard is read on the main actor; only the decode moves off it.
    @MainActor
    static func loadFromClipboard(_ pasteboard: NSPasteboard) async -> CharacterSheetLoadOutcome {
        guard PetClipboardImporter.hasSupportedImage(on: pasteboard) else { return .empty }
        guard let data = PetClipboardImporter.sheetData(from: pasteboard) else { return .invalid(.unreadable) }
        return await Task.detached(priority: .userInitiated) { inspect(data) }.value
    }

    /// Decode individual PNGs for the advanced per-frame editor, skipping any that is not usable.
    static func optimizedImages(from urls: [URL]) async -> [NSImage] {
        await Task.detached(priority: .userInitiated) {
            urls.compactMap { url in
                autoreleasepool {
                    PetSpriteSheetImporter.readPNG(from: url)
                        .flatMap(PetSpriteSheetImporter.optimizedImage)?
                        .image
                }
            }
        }.value
    }

    private static func inspect(_ data: Data) -> CharacterSheetLoadOutcome {
        switch PetSpriteSheetImporter.inspect(data) {
        case let .success(candidate): .valid(candidate)
        case let .failure(reason): .invalid(reason)
        }
    }
}
