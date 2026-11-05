import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct SetupWizardPreviewTests {
    @Test func previewPlayerHoldsEachShotBeforeAdvancing() async throws {
        let images = try Fixture.sheetImages()
        let view = NSImageView()
        var seen: [ObjectIdentifier] = []
        var player: PetPreviewPlayer?
        let recorder: @MainActor (TimeInterval) async -> Void = { _ in
            if let image = view.image {
                seen.append(ObjectIdentifier(image))
            }
            if seen.count >= 3 {
                player?.stop()
            }
        }
        player = PetPreviewPlayer(showImage: { view.image = $0 }, sleep: recorder)
        player?.setImages(images)
        player?.play(.enter)
        for _ in 0 ..< 200 where seen.count < 3 {
            await Task.yield()
        }
        player?.stop()
        #expect(seen.first == ObjectIdentifier(images[.enter][0]))
        #expect(seen.count >= 2)
    }

    @Test(arguments: [PetImageCategory.typing, .enter])
    func reactionPreviewPlaysTheKeyThenReturnsToIdle(category: PetImageCategory) async throws {
        let images = try Fixture.sheetImages()
        let view = NSImageView()
        var seen: [ObjectIdentifier] = []
        var player: PetPreviewPlayer?
        let expectedCount = images[category].count + 1
        player = PetPreviewPlayer(showImage: { view.image = $0 }, sleep: { _ in
            if let image = view.image {
                seen.append(ObjectIdentifier(image))
            }
            if seen.count >= expectedCount {
                player?.stop()
            }
        })
        player?.setImages(images)
        player?.playReaction(category)
        for _ in 0 ..< 200 where seen.count < expectedCount {
            await Task.yield()
        }
        player?.stop()
        #expect(seen.count == expectedCount)
        #expect(seen.first == ObjectIdentifier(images[category][0]))
        #expect(seen.last == ObjectIdentifier(images[.idle][0]))
    }

    @Test func repeatedTypingDoesNotRestartTheCurrentAnimation() async throws {
        let images = try Fixture.sheetImages()
        var seen: [ObjectIdentifier] = []
        var pending: CheckedContinuation<Void, Never>?
        let player = PetPreviewPlayer(showImage: { image in
            if let image {
                seen.append(ObjectIdentifier(image))
            }
        }, sleep: { _ in
            await withCheckedContinuation { pending = $0 }
        })
        defer {
            player.stop()
            pending?.resume()
        }
        player.setImages(images)
        player.playReaction(.typing)
        for _ in 0 ..< 200 where pending == nil {
            await Task.yield()
        }
        let firstDelay = try #require(pending)
        for _ in 0 ..< 5 {
            player.playReaction(.typing)
        }
        await Task.yield()
        #expect(seen == [ObjectIdentifier(images[.typing][0])])

        pending = nil
        firstDelay.resume()
        for _ in 0 ..< 200 where pending == nil {
            await Task.yield()
        }
        let secondDelay = try #require(pending)
        #expect(seen == [ObjectIdentifier(images[.typing][0]), ObjectIdentifier(images[.typing][1])])

        pending = nil
        player.playReaction(.enter)
        secondDelay.resume()
        for _ in 0 ..< 200 where pending == nil {
            await Task.yield()
        }
        #expect(pending != nil)
        #expect(seen.last == ObjectIdentifier(images[.enter][0]))
    }

    @Test func previewImageViewUpdatesAndClearsItsLayer() throws {
        let view = PreviewImageView()
        let image = try #require(Fixture.sheetImages()[.idle].first)
        view.image = image
        #expect(view.layer?.contents != nil)
        view.image = nil
        #expect(view.layer?.contents == nil)
    }

    @Test func previewPaneSwapsPlaceholderForThePet() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        #expect(!wizard.previewPane.hasPet)
        try wizard.previewPane.showPet(Fixture.sheetImages(), caption: "ready")
        #expect(wizard.previewPane.hasPet)
    }

    @Test func demoPetIsShownWithoutRegisteringIt() throws {
        let wizard = try Fixture.makeWizard(demoURL: Fixture.sheetURL())
        defer { wizard.close() }
        #expect(wizard.previewPane.hasPet)
        #expect(!wizard.hasImage)
    }

    @Test func rerenderingTheSameFramesResumesPlayback() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let pane = wizard.previewPane
        let images = try Fixture.sheetImages()
        pane.showPet(images, caption: "ready")
        #expect(pane.isPlayingPreview)

        pane.stopPlayback()
        #expect(!pane.isPlayingPreview)

        pane.showPet(images, caption: "ready")
        #expect(pane.isPlayingPreview)
    }

    @Test func rerenderingInCellsModeLeavesPlaybackStopped() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let pane = wizard.previewPane
        let images = try Fixture.sheetImages()
        pane.showPet(images, caption: "ready")

        pane.modeControl.selectedSegment = 1
        _ = pane.modeControl.sendAction(pane.modeControl.action, to: pane.modeControl.target)
        #expect(!pane.isPlayingPreview)

        pane.showPet(images, caption: "ready")
        #expect(!pane.isPlayingPreview)
    }

    @Test func previewLoopsEveryCategoryOfTheImportedSheet() throws {
        let shots = try PetPreviewPlayer.demoShots(for: Fixture.sheetImages())
        #expect(shots.count == 9)
        #expect(shots.allSatisfy { $0.seconds > 0 })
    }

    /// The pane captured its layer colors once at init. Flipping the appearance afterwards must
    /// re-resolve them, or a dark-initialized backdrop stays dark under the light appearance.
    @Test func previewBackdropFollowsAnAppearanceChange() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let pane = wizard.previewPane
        let dark = try #require(NSAppearance(named: .darkAqua))
        let light = try #require(NSAppearance(named: .aqua))

        pane.appearance = dark
        pane.viewDidChangeEffectiveAppearance()
        let darkBackdrop = pane.layer?.backgroundColor

        pane.appearance = light
        pane.viewDidChangeEffectiveAppearance()
        let lightBackdrop = pane.layer?.backgroundColor

        // A single init-time resolution would leave both equal; the backdrop must re-resolve.
        #expect(darkBackdrop != lightBackdrop)
        #expect(darkBackdrop == resolvedControlBackground(dark))
        #expect(lightBackdrop == resolvedControlBackground(light))
    }

    @Test func appearanceChangePreservesTheActiveDropHighlight() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let pane = wizard.previewPane
        pane.isDropTargeted = true
        for name in [NSAppearance.Name.darkAqua, .aqua] {
            pane.appearance = try #require(NSAppearance(named: name))
            pane.viewDidChangeEffectiveAppearance()
            var accent = NSColor.controlAccentColor.cgColor
            pane.effectiveAppearance.performAsCurrentDrawingAppearance {
                accent = NSColor.controlAccentColor.cgColor
            }
            #expect(pane.layer?.borderColor == accent)
            #expect(pane.layer?.borderWidth == 2)
        }
        pane.isDropTargeted = false
        #expect(pane.layer?.borderWidth == pane.idleBorderWidth)
    }

    private func resolvedControlBackground(_ appearance: NSAppearance) -> CGColor {
        var color = NSColor.controlBackgroundColor.cgColor
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.controlBackgroundColor.cgColor
        }
        return color
    }
}
