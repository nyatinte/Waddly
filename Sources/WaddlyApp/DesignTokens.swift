import AppKit
import SwiftUI

/// The shared type, shape, auxiliary-control, and status tokens from `DESIGN.md`.
///
/// `LayoutMetrics` owns the window-level layout values (content inset, section/column/action gaps,
/// action height, footer inset, preview width). This type owns the scales that the dense editor and
/// future surfaces share, so a new view cannot invent another 9 pt label or 5 pt radius.
enum DesignTokens {
    enum Typography {
        static let display = Font.system(size: 25, weight: .semibold)
        static let title = Font.system(size: 15, weight: .semibold)
        static let heading = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let callout = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let action = Font.system(size: 13, weight: .medium)
        static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
    }

    enum Spacing {
        // Token names follow the DESIGN.md scale; the short names are the shared vocabulary.
        // swiftlint:disable identifier_name
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        // swiftlint:enable identifier_name
    }

    enum Radius {
        static let control: CGFloat = 6
        static let surface: CGFloat = 8
        static let card: CGFloat = 12
        static let preview: CGFloat = 16
    }

    enum Control {
        static let auxiliaryHeight: CGFloat = 28
        static let hitTargetMin: CGFloat = 20
    }

    enum Status {
        static let positive = Color(nsColor: dynamic(
            light: NSColor(srgbRed: 31 / 255, green: 122 / 255, blue: 51 / 255, alpha: 1),
            dark: NSColor(srgbRed: 74 / 255, green: 222 / 255, blue: 128 / 255, alpha: 1)
        ))
        static let critical = Color(nsColor: dynamic(
            light: NSColor(srgbRed: 198 / 255, green: 40 / 255, blue: 40 / 255, alpha: 1),
            dark: NSColor(srgbRed: 255 / 255, green: 123 / 255, blue: 114 / 255, alpha: 1)
        ))
        static let warning = Color(nsColor: dynamic(
            light: NSColor(srgbRed: 178 / 255, green: 80 / 255, blue: 0, alpha: 1),
            dark: NSColor(srgbRed: 255 / 255, green: 179 / 255, blue: 64 / 255, alpha: 1)
        ))

        private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            }
        }
    }
}
