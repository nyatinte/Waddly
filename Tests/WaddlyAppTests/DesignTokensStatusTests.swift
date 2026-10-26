import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp

/// Status text is the small print ``DESIGN.md`` requires 4.5:1 for, and the system green/red that the
/// remaining Character Import and setup prompt-feedback lines used are not text tokens. These tests
/// pin the pair `DesignTokens.Status` resolves in each appearance so the migration cannot drift back.
@MainActor struct DesignTokensStatusTests {
    @Test func theStatusTokensResolveTheDocumentedLightAndDarkPairs() throws {
        try expectStatus(DesignTokens.Status.positive, in: .aqua, red: 31, green: 122, blue: 51)
        try expectStatus(DesignTokens.Status.positive, in: .darkAqua, red: 74, green: 222, blue: 128)
        try expectStatus(DesignTokens.Status.critical, in: .aqua, red: 198, green: 40, blue: 40)
        try expectStatus(DesignTokens.Status.critical, in: .darkAqua, red: 255, green: 123, blue: 114)
    }

    /// The point of the migration: status text must not fall back to the system colors, which are
    /// outside the contrast contract and differ from the tokens in both appearances.
    @Test func statusTextTokensAreNotTheSystemColorsTheyReplaced() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            try expectDiffers(
                DesignTokens.Status.critical,
                from: .systemRed,
                in: appearance,
                tolerance: 0.02
            )
            try expectDiffers(
                DesignTokens.Status.positive,
                from: .systemGreen,
                in: appearance,
                tolerance: 0.02
            )
        }
    }
}

@MainActor
private extension DesignTokensStatusTests {
    /// One documented Light/Dark pair of a status token, component by component.
    func expectStatus(
        _ color: Color,
        in name: NSAppearance.Name,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) throws {
        let appearance = try #require(NSAppearance(named: name))
        let actual = try #require(resolved(color, appearance))
        #expect(abs(actual.redComponent - red / 255) < 0.01, "\(name.rawValue) red")
        #expect(abs(actual.greenComponent - green / 255) < 0.01, "\(name.rawValue) green")
        #expect(abs(actual.blueComponent - blue / 255) < 0.01, "\(name.rawValue) blue")
    }

    /// A token and the system color it replaced have to separate on at least one channel, so a
    /// regression to the system color fails loudly instead of passing on a rounding coincidence.
    func expectDiffers(
        _ token: Color,
        from system: NSColor,
        in appearance: NSAppearance,
        tolerance: CGFloat
    ) throws {
        let tokenColor = try #require(resolved(token, appearance))
        let systemColor = try #require(system.resolved(in: appearance))
        let channels = [
            abs(tokenColor.redComponent - systemColor.redComponent),
            abs(tokenColor.greenComponent - systemColor.greenComponent),
            abs(tokenColor.blueComponent - systemColor.blueComponent)
        ]
        #expect(
            channels.contains { $0 > tolerance },
            "\(appearance.name.rawValue): the token still resolves to the system color it replaced"
        )
    }
}

@MainActor
private func resolved(_ color: Color, _ appearance: NSAppearance) -> NSColor? {
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance {
        resolved = NSColor(color).usingColorSpace(.sRGB)
    }
    return resolved
}

private extension NSColor {
    func resolved(in appearance: NSAppearance) -> NSColor? {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance { resolved = self.usingColorSpace(.sRGB) }
        return resolved
    }
}
