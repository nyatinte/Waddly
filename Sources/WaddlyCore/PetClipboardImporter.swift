import AppKit

/// Reads a sprite sheet from the general pasteboard, but only in response to an explicit paste.
///
/// The availability check reads only the pasteboard's types and file-URL objects; the PNG bytes are
/// read in `sheetData(from:)`, which callers run once per explicit "Paste" click or ⌘V. A copied PNG
/// file is preferred over its pixels so the exact bytes are validated, and a copied bitmap is
/// normalized to PNG before validation.
public enum PetClipboardImporter {
    /// The pixel representations Waddly can normalize. A `NSImage` copy usually arrives as TIFF.
    static let pixelTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    /// Whether an explicit paste would have something to offer. Never reads image pixels.
    public static func hasSupportedImage(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains(where: pixelTypes.contains) == true || pngFileURL(on: pasteboard) != nil
    }

    /// PNG bytes for the supported clipboard contents, or `nil` when nothing usable is present.
    public static func sheetData(from pasteboard: NSPasteboard) -> Data? {
        if let url = pngFileURL(on: pasteboard), let data = PetSpriteSheetImporter.readPNG(from: url) {
            return data
        }
        if let png = pasteboard.data(forType: .png) {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff) {
            return pngData(fromTIFF: tiff)
        }
        return nil
    }

    /// The first copied PNG file URL, if the pasteboard carries one.
    static func pngFileURL(on pasteboard: NSPasteboard) -> URL? {
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return nil }
        return urls.first { $0.pathExtension.lowercased() == "png" }
    }

    static func pngData(fromTIFF data: Data) -> Data? {
        NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
    }
}
