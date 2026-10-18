import AppKit
import UniformTypeIdentifiers

enum PetShareClipboard {
    static func copyPNG(_ data: Data, to pasteboard: NSPasteboard = .general) -> Bool {
        copy(data, type: UTType.png.identifier, fileURL: nil, to: pasteboard)
    }

    /// Copies the movie the way Finder copies a file, not just as bytes.
    ///
    /// Browsers and chat apps attach an upload only when the pasteboard names a file, so a data-only
    /// video pastes as nothing at all in the X composer. `fileURL` must stay readable after the share
    /// window closes; `publishForPasteboard` provides that file.
    static func copyMovie(_ data: Data, fileURL: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        copy(data, type: UTType.mpeg4Movie.identifier, fileURL: fileURL, to: pasteboard)
    }

    /// Writes `data` beside the pasteboard's other files so the file reference outlives the share
    /// window's temporary export directory. The name is stable, so a later copy replaces the previous
    /// export instead of accumulating them.
    static func publishForPasteboard(_ data: Data, named name: String, in directory: URL? = nil) -> URL? {
        guard let directory = directory ?? pasteboardDirectory else { return nil }
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    /// A development build keeps its own folder, like `PetImageLocation` does for imported frames.
    private static var pasteboardDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(
                PetImageLocation.directoryName(for: Bundle.main.bundleIdentifier),
                isDirectory: true
            )
            .appendingPathComponent("Pasteboard", isDirectory: true)
    }

    private static func copy(_ data: Data, type: String, fileURL: URL?, to pasteboard: NSPasteboard) -> Bool {
        let item = NSPasteboardItem()
        item.setData(data, forType: NSPasteboard.PasteboardType(type))
        if let fileURL {
            item.setString(fileURL.absoluteString, forType: .fileURL)
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
