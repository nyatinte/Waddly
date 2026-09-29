import AppKit
import Darwin
import Foundation

private enum IconError: Error {
    case usage
    case imageNotFound
    case pngEncodingFailed
}

@MainActor
private func makeIcon() throws {
    guard CommandLine.arguments.count == 3 else { throw IconError.usage }
    guard let pet = NSImage(contentsOfFile: CommandLine.arguments[1]) else { throw IconError.imageNotFound }

    let canvas = NSImage(size: NSSize(width: 1024, height: 1024))
    canvas.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.22, blue: 0.38, alpha: 1),
        NSColor(calibratedRed: 0.18, green: 0.52, blue: 0.70, alpha: 1)
    ])
    gradient?.draw(in: bounds, angle: 90)

    NSColor(calibratedRed: 0.73, green: 0.91, blue: 0.96, alpha: 0.20).setFill()
    NSBezierPath(ovalIn: NSRect(x: 172, y: 218, width: 680, height: 680)).fill()

    NSColor(calibratedRed: 0.03, green: 0.12, blue: 0.20, alpha: 0.24).setFill()
    NSBezierPath(ovalIn: NSRect(x: 300, y: 174, width: 424, height: 58)).fill()

    pet.draw(in: NSRect(x: 158, y: 150, width: 708, height: 708))
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.pngEncodingFailed
    }
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}

do {
    try MainActor.assumeIsolated { try makeIcon() }
} catch IconError.usage {
    FileHandle.standardError.write(Data("Usage: make-icon.swift input.png output.png\n".utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("make-icon.swift: \(error)\n".utf8))
    exit(1)
}
