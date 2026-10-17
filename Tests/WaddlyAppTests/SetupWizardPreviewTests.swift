import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct SetupWizardPreviewTests {
    @Test func choosingASheetRegistersItRightAway() async throws {
        let images = try Fixture.sheetImages()
        let wizard = try Fixture.makeWizard(
            previewResult: images,
            confirmResult: true
        )
        defer { wizard.close() }
        let url = try Fixture.sheetURL()
        await wizard.importImage(from: url).value
        #expect(wizard.didRegisterPet)
        #expect(wizard.importedFileName == url.lastPathComponent)
        #expect(wizard.previewPane.hasPet)
    }

    @Test func unreadableSheetLeavesThePreviousSetAlone() async throws {
        let state = Fixture.State()
        let previous = try Fixture.sheetImages()
        state.images = previous
        let wizard = try Fixture.makeWizard(state: state, previewResult: nil)
        defer { wizard.close() }
        try await wizard.importImage(from: Fixture.sheetURL()).value
        #expect(wizard.hasImage)
        #expect(wizard.currentPetImages()[.idle].first === previous[.idle].first)
        #expect(!wizard.didRegisterPet)
        #expect(wizard.currentStep == .pet)
    }

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
        player = PetPreviewPlayer(imageView: view, sleep: recorder)
        player?.setImages(images)
        player?.play(.enter)
        for _ in 0 ..< 200 where seen.count < 3 {
            await Task.yield()
        }
        player?.stop()
        #expect(seen.first == ObjectIdentifier(images[.enter][0]))
        #expect(seen.count >= 2)
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
