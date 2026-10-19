import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Renders real AppKit/SwiftUI content off screen for the character-import documentation captures.
///
/// Opt-in only: with `WADDLY_CAPTURE_CHARACTER_IMPORT=1` the tests write PNGs into
/// `docs/images/character-import`; otherwise they do nothing, so `mise run test` stays side-effect
/// free. These are content-view renders (`cacheDisplay(in:to:)`), not OS screenshots.
@MainActor
enum CaptureHarness {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["WADDLY_CAPTURE_CHARACTER_IMPORT"] == "1"
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var outputDirectory: URL {
        repositoryRoot.appendingPathComponent("docs/images/character-import", isDirectory: true)
    }

    static func prepare() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    static func sheetURL() throws -> URL {
        try SetupWizardFixture.sheetURL()
    }

    static func appearance(dark: Bool) -> NSAppearance {
        NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
    }

    static func localized(_ language: AppLanguage) throws -> LocalizationController {
        let name = "WaddlyTests.capture.\(UUID().uuidString)"
        let settings = try AppSettings(defaults: #require(UserDefaults(suiteName: name)))
        settings.appLanguage = language
        let resources = try #require(Bundle(url: repositoryRoot.appendingPathComponent("macos")))
        return LocalizationController(settings: settings, resources: resources)
    }

    /// A pasteboard that either holds the example sheet as PNG pixels or nothing.
    static func pasteboard(holdsSheet: Bool) throws -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WaddlyTests.capture.\(UUID().uuidString)"))
        pasteboard.clearContents()
        guard holdsSheet else { return pasteboard }
        let frames = try #require(try PetSpriteSheetImporter.frames(from: Data(contentsOf: sheetURL())))
        let frame = try #require(frames[.idle].first)
        try pasteboard.setData(#require(PetSpriteSheetImporter.pngData(for: frame)), forType: .png)
        return pasteboard
    }

    /// Composite the view's own render onto the appearance's window background, bounded to 1400 px on
    /// the long edge, and write it as `<name>.png`.
    static func write(_ view: NSView, dark: Bool, named name: String) throws {
        let appearance = appearance(dark: dark)
        view.appearance = appearance
        // Let the pending SwiftUI transaction for the state just set land, then let the preview
        // player's first frame task publish, before capturing.
        settle(view)
        let bounds = view.bounds
        guard let captured = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            Issue.record("no bitmap for \(name)")
            return
        }
        view.cacheDisplay(in: bounds, to: captured)
        let scale = min(1, 1400 / Double(max(captured.pixelsWide, captured.pixelsHigh)))
        let width = max(1, Int(Double(captured.pixelsWide) * scale))
        let height = max(1, Int(Double(captured.pixelsHigh) * scale))
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: canvas) else {
            Issue.record("no canvas for \(name)")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        if let image = captured.cgImage {
            context.cgContext.interpolationQuality = .high
            context.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        NSGraphicsContext.restoreGraphicsState()
        let data = try #require(canvas.representation(using: .png, properties: [:]))
        try data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }

    /// Lay out, display, and run the loop a couple of times so the SwiftUI update pass lands and the
    /// preview player's first frame task publishes before the capture.
    static func settle(_ view: NSView) {
        for _ in 0 ..< 3 {
            view.needsLayout = true
            view.needsDisplay = true
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        view.layoutSubtreeIfNeeded()
    }

    /// The preview pane inside a captured content view, so a render can show its nine-cell mode.
    static func previewPane(in view: NSView) -> SetupPreviewPane? {
        if let pane = view as? SetupPreviewPane {
            return pane
        }
        for subview in view.subviews {
            if let found = previewPane(in: subview) {
                return found
            }
        }
        return nil
    }

    static func setPreviewPane(_ pane: SetupPreviewPane, cells: Bool) {
        pane.modeControl.selectedSegment = cells ? 1 : 0
        pane.modeControl.sendAction(pane.modeControl.action, to: pane.modeControl.target)
    }

    /// Push the staged frames into the embedded AppKit preview pane. SwiftUI's final update pass runs
    /// after the last capture, so the harness does this once more before rendering the valid state;
    /// the live app reaches the same state through `updateNSView` on the player's own run loop.
    static func showStagedFrames(_ model: CharacterImportModel, in content: NSView) {
        guard let pane = previewPane(in: content),
              let frames = model.stagedFrames, frames.isComplete else { return }
        pane.showPet(frames, caption: "", sleeping: false)
    }

    static func suffix(_ language: AppLanguage, _ dark: Bool) -> String {
        "\(language == .english ? "en" : "ja")-\(dark ? "dark" : "light")"
    }
}
