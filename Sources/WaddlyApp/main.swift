import AppKit
import ImageIO
import UniformTypeIdentifiers
import WaddlyCore

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--self-test-sprite-sheet" {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])),
          let images = PetSpriteSheetImporter.frames(from: data),
          images[.idle].count == 2, images[.typing].count == 4,
          images[.sleep].count == 2, images[.enter].count == 1,
          PetSpriteSheetImporter.image(from: data) != nil else {
        fatalError("3×3 transparent PNG import failed")
    }
    let savedFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("Waddly-self-test-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: savedFile) }
    do {
        try PetSpriteSheetImporter.save(data, to: savedFile)
    } catch {
        fatalError("3×3 PNG save failed: \(error)")
    }
    guard PetSpriteSheetImporter.load(from: savedFile) != nil else {
        fatalError("3×3 PNG reload failed")
    }
    print("3×3 transparent PNG import and persistence passed")
    exit(0)
}

if CommandLine.arguments.contains("--self-test") {
    precondition(PetPhase.after(0) == .typing)
    precondition(PetPhase.after(2.5) == .idle)
    precondition(PetPhase.after(25) == .sleeping)
    precondition(PetPhase.after(325) == .frozen)
    precondition(TypingMotion.off.amplitude == 0)
    precondition(TypingMotion.weak.amplitude == 5)
    precondition(TypingMotion.strong.amplitude > TypingMotion.weak.amplitude)
    precondition(KeyboardMonitor.isEnterKeyCode(36))
    precondition(KeyboardMonitor.isEnterKeyCode(76))
    precondition(!KeyboardMonitor.isEnterKeyCode(0))
    precondition(moving(["first", "second", "third"], from: 0, to: 2) == ["second", "third", "first"])
    precondition(moving(["first", "second", "third"], from: 2, to: 0) == ["third", "first", "second"])
    precondition(moving(["only"], from: 1, to: 0) == nil)
    let bundled = PetImageSet.bundled(from: Array(repeating: NSImage(size: NSSize(width: 1, height: 1)), count: 16))
    precondition(bundled?[.idle].count == 2)
    precondition(bundled?[.typing].count == 7)
    precondition(bundled?[.sleep].count == 2)
    precondition(bundled?[.enter].count == 3)
    guard let context = CGContext(
        data: nil,
        width: 2_048,
        height: 2_048,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let largeImage = context.makeImage() else {
        fatalError("Image optimization test setup failed")
    }
    let sourceData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        sourceData,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fatalError("Image optimization test setup failed")
    }
    CGImageDestinationAddImage(destination, largeImage, nil)
    guard CGImageDestinationFinalize(destination),
          let optimized = PetSpriteSheetImporter.optimizedImage(from: sourceData as Data),
          let optimizedSource = CGImageSourceCreateWithData(optimized.pngData as CFData, nil),
          let optimizedProperties = CGImageSourceCopyPropertiesAtIndex(optimizedSource, 0, nil) as? [CFString: Any],
          let optimizedWidth = optimizedProperties[kCGImagePropertyPixelWidth] as? Int,
          let optimizedHeight = optimizedProperties[kCGImagePropertyPixelHeight] as? Int,
          optimized.wasDownsampled,
          optimizedWidth == 1_024,
          optimizedHeight == 1_024,
          optimized.image.size.width == 1_024,
          optimized.image.size.height == 1_024 else {
        fatalError("Image downsampling failed")
    }
    print("Pet phases, image categories, and 1024px image optimization passed")
    exit(0)
}

@MainActor
private func runApplication() {
    let app = NSApplication.shared
    let appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.setActivationPolicy(.regular)
    app.run()
}

runApplication()
