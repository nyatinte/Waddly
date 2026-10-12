import AppKit
import UniformTypeIdentifiers

enum PetShareClipboard {
    static func copyPNG(_ data: Data, to pasteboard: NSPasteboard = .general) -> Bool {
        copy(data, type: UTType.png.identifier, to: pasteboard)
    }

    static func copyMovie(_ data: Data, to pasteboard: NSPasteboard = .general) -> Bool {
        copy(data, type: UTType.mpeg4Movie.identifier, to: pasteboard)
    }

    private static func copy(_ data: Data, type: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
    }
}
