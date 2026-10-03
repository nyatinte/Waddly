#!/usr/bin/env swift
import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("check_menu_bar_icon: \(message)\n".utf8))
    exit(EXIT_FAILURE)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: swift Tools/check_menu_bar_icon.swift <app-bundle>")
}

let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let bundle = Bundle(url: bundleURL),
      let iconURL = bundle.url(forResource: "waddly-menubar", withExtension: "pdf"),
      let image = NSImage(contentsOf: iconURL), image.isValid
else {
    fail("The packaged menu bar PDF could not be loaded.")
}

image.size = NSSize(width: 24, height: 24)
guard let data = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: data)
else {
    fail("The packaged menu bar PDF could not be rendered.")
}

let hasVisiblePixels = (0 ..< bitmap.pixelsHigh).contains { row in
    (0 ..< bitmap.pixelsWide).contains { column in
        (bitmap.colorAt(x: column, y: row)?.alphaComponent ?? 0) > 0
    }
}

guard hasVisiblePixels else {
    fail("The packaged menu bar icon is empty.")
}
