import AppKit
import Testing
@testable import WaddlyApp

/// The import sheet's background checkbox is what the preview is checked against, so it has to be
/// the same control the accessory reads.
struct SpriteSheetPreviewAccessoryTests {
    @MainActor
    @Test func theVisibleCheckboxDrivesThePreviewBackground() throws {
        let accessory = try makeAccessory(prefersDarkBackground: false)
        let checkbox = try checkbox(in: accessory)
        let background = try previewBackground(in: accessory)

        #expect(checkbox.state == .off)
        let light = try #require(background())

        checkbox.setNextState()
        try sendTestAction(checkbox)
        #expect(checkbox.state == .on)
        let dark = try #require(background())
        #expect(dark != light)

        // And back: the checkbox has to keep matching the preview in both directions.
        checkbox.setNextState()
        try sendTestAction(checkbox)
        #expect(checkbox.state == .off)
        #expect(background() == light)
    }

    /// The preview starts dark for a dark pet, and the control has to say so.
    @MainActor
    @Test func theCheckboxStartsOutMatchingThePreferredBackground() throws {
        let dark = try checkbox(in: makeAccessory(prefersDarkBackground: true))
        #expect(dark.state == .on)

        let light = try checkbox(in: makeAccessory(prefersDarkBackground: false))
        #expect(light.state == .off)
    }

    @MainActor
    private func makeAccessory(prefersDarkBackground: Bool) throws -> SpriteSheetPreviewAccessory {
        _ = NSApplication.shared
        let name = "WaddlyTests.accessory.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        return SpriteSheetPreviewAccessory(
            preview: NSImage(size: NSSize(width: 30, height: 30)),
            cellSize: 3,
            displaySize: 240,
            localization: LocalizationController(settings: AppSettings(defaults: defaults)),
            prefersDarkBackground: prefersDarkBackground
        )
    }

    @MainActor
    private func checkbox(in accessory: SpriteSheetPreviewAccessory) throws -> NSButton {
        try #require(SetupWizardFixture.descendants(of: accessory).compactMap { $0 as? NSButton }.first)
    }

    @MainActor
    private func previewBackground(in accessory: SpriteSheetPreviewAccessory) throws -> () -> CGColor? {
        let imageView = try #require(
            SetupWizardFixture.descendants(of: accessory).compactMap { $0 as? PixelImageView }.first
        )
        return { imageView.layer?.backgroundColor }
    }
}
