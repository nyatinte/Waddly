import AppKit
import SwiftUI
import Testing
@testable import WaddlyApp
import WaddlyCore

/// The animation editor surface: lifecycle, required content minimum, and the real drop path.
@Suite(.serialized) @MainActor struct AnimationSettingsTests {
    /// Closing releases the app's references and detaches the hosted SwiftUI view. Immediate
    /// NSHostingView deallocation cannot be asserted: SwiftUI retains every hosting view past window
    /// close (verified with a bare NSHostingView<Text>), so that framework retention is reported here
    /// rather than asserted. Reopening builds a fresh model and shows the current pet images.
    @Test func releaseOnCloseAndRebuildOnReopen() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.showImageSettings()
        let window = try #require(app.imageSettingsWindow)
        #expect(window.contentView is NSHostingView<AnimationSettingsView>)
        let first = try #require(app.animationSettingsModel)
        #expect(first.thumbnails(for: .idle).count == 2)
        #expect(first.thumbnails(for: .typing).count == 4)
        #expect(first.thumbnails(for: .sleep).count == 2)
        #expect(first.thumbnails(for: .enter).count == 1)

        // An edit while the editor is open flows through the same persistence path and refreshes
        // the model without reopening the window.
        await app.removeImage(at: 0, from: .idle)?.value
        #expect(first.thumbnails(for: .idle).count == 1)
        #expect(app.petImages[.idle].count == 1)

        window.close()
        #expect(app.imageSettingsWindow == nil)
        #expect(app.animationSettingsModel == nil)
        #expect(window.contentView == nil)

        app.showImageSettings()
        let second = try #require(app.animationSettingsModel)
        #expect(second !== first)
        #expect(second.thumbnails(for: .idle).count == 1)
    }

    /// The window's minimum must be a *content* minimum that fits all four fixed rows plus the
    /// instructions. The old frame-based `minSize` subtracted the title bar and clipped the last row.
    @Test func minimumContentFitsAllFourRows() throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        app.showImageSettings()
        let window = try #require(app.imageSettingsWindow)
        let minimum = AnimationSettingsMetrics.contentMinSize
        #expect(window.contentMinSize == minimum)
        let rows = AnimationSettingsMetrics.rowHeight * CGFloat(PetImageCategory.allCases.count)
        let gaps = AnimationSettingsMetrics.rowSpacing * CGFloat(PetImageCategory.allCases.count + 1)
        #expect(minimum.height >= rows + gaps
            + AnimationSettingsMetrics.instructionBlockHeight + AnimationSettingsMetrics.contentInset * 2)
        // 640 was the old frame height, which left the content shorter than four rows.
        #expect(minimum.height > 640)
    }

    /// A drop reaches the editor through the model's AppDelegate-wired callback and lands in the
    /// same `addImages` persistence path as the open panel — not just a stubbed model callback.
    @Test func droppingAPNGThroughTheModelAddsAnImage() async throws {
        let fixture = try AppIntegrationFixture()
        defer { fixture.close() }
        let app = fixture.app
        try await app.persistPetImages(fixture.exampleImages())
        app.showImageSettings()
        let model = try #require(app.animationSettingsModel)
        let before = app.petImages[.idle].count
        let frame = try #require(app.petImages[.idle].first)
        let pngURL = fixture.directory.appendingPathComponent("dropped.png")
        try #require(PetSpriteSheetImporter.pngData(for: frame)).write(to: pngURL)

        model.drop([pngURL], on: .idle)

        #expect(await waitForImageCount(app, category: .idle, count: before + 1))
        #expect(model.thumbnails(for: .idle).count == before + 1)
    }
}

private extension AnimationSettingsTests {
    /// The editor's queue runs a detached prep task, so poll until the edit commits.
    func waitForImageCount(_ app: AppDelegate, category: PetImageCategory, count: Int) async -> Bool {
        for _ in 0 ..< 300 {
            if app.petImages[category].count == count {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
