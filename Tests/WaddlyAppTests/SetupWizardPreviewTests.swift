import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Preview pane, demo pet, and player sequencing.
@Suite(.serialized) @MainActor struct SetupWizardPreviewTests {
    /// Choosing a file is the decision: it must register immediately and never gate 次へ.
    @Test func choosingASheetRegistersItRightAway() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(
            state: state,
            previewResult: Fixture.sheetImages(),
            confirmResult: true
        )
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)

        try wizard.importImage(from: Fixture.sheetURL())
        try await Fixture.waitUntil { wizard.hasImage }

        #expect(try Fixture.button("goNext", in: content).isEnabled)
        #expect(Fixture.descendants(of: content).compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == wizard.localizedString(.setupRegisteredTitle) })
        // The 3x3 facts are shown without asking for a second confirmation.
        #expect(Fixture.descendants(of: content).compactMap { $0 as? NSTextField }
            .contains { $0.stringValue.contains("768") })
    }

    @Test func anUnreadableSheetLeavesThePreviousSetAlone() async throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(state: state, previewResult: nil)
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)

        try wizard.importImage(from: Fixture.sheetURL())
        // The import path raises the alert; the wizard itself simply stays on the choices.
        try await Fixture.waitUntil {
            Fixture.descendants(of: content).compactMap { $0 as? SetupOptionCard }.count == 2
        }

        #expect(!wizard.hasImage)
        #expect(!Fixture.descendants(of: content).compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == wizard.localizedString(.setupRegisteredTitle) })
    }

    @Test func previewPlayerHoldsEachShotBeforeAdvancing() async throws {
        let images = try Fixture.sheetImages()
        let view = NSImageView()
        var seen: [ObjectIdentifier] = []
        var player: PetPreviewPlayer?
        // The fake clock records what is on screen for every step of the sequence.
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
        for _ in 0 ..< 200 where !(seen.count >= 3) {
            await Task.yield()
        }
        player?.stop()
        // The Enter frame must be on screen for its own duration, not replaced immediately.
        #expect(seen.first == ObjectIdentifier(images[.enter][0]))
        #expect(seen.count >= 2)
    }

    @Test func previewPaneSwapsItsPlaceholderForThePet() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        let pane = try #require(Fixture.descendants(of: content).compactMap { $0 as? SetupPreviewPane }.first)
        #expect(!pane.hasPet)
        try pane.showPet(Fixture.sheetImages(), caption: "ready")
        #expect(pane.hasPet)
    }

    @Test func demoPetIsShownWithoutRegisteringIt() throws {
        let state = Fixture.State()
        let wizard = try Fixture.makeWizard(state: state, demoURL: Fixture.sheetURL())
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        let pane = try #require(Fixture.descendants(of: content).compactMap { $0 as? SetupPreviewPane }.first)
        #expect(pane.hasPet)
        // The demo is a preview only: no image is registered, so setup still cannot continue.
        #expect(!wizard.hasImage)
        #expect(try !Fixture.button("goNext", in: content).isEnabled)
    }

    /// Closing setup stops the preview, and reopening reuses this pane with the same frames and the
    /// same caption. That used to look like "nothing changed", which left the pet frozen on the
    /// reopened screen until the user touched a control.
    @Test func rerenderingTheSameFramesResumesPlayback() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        let pane = try #require(Fixture.descendants(of: content).compactMap { $0 as? SetupPreviewPane }.first)
        let images = try Fixture.sheetImages()
        pane.showPet(images, caption: "ready")
        #expect(pane.isPlayingPreview)

        // What closing the window does on the way out.
        pane.stopPlayback()
        #expect(!pane.isPlayingPreview)

        pane.showPet(images, caption: "ready")
        #expect(pane.isPlayingPreview)
    }

    /// The cells view is an inspection, so a rerender must not quietly start the loop behind it.
    @Test func rerenderingInCellsModeLeavesPlaybackStopped() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        let pane = try #require(Fixture.descendants(of: content).compactMap { $0 as? SetupPreviewPane }.first)
        let images = try Fixture.sheetImages()
        pane.showPet(images, caption: "ready")

        pane.modeControl.selectedSegment = 1
        _ = pane.modeControl.sendAction(pane.modeControl.action, to: pane.modeControl.target)
        #expect(!pane.isPlayingPreview)

        pane.showPet(images, caption: "ready")
        #expect(!pane.isPlayingPreview)
    }

    @Test func copyFeedbackStaysSilentUntilTheCopyIsAttempted() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        try Fixture.optionCard("showChatGPTGuide", in: content).activate()
        let copied = wizard.localizedString(.setupPromptCopied)
        let labels = Fixture.descendants(of: content).compactMap { $0 as? NSTextField }.map(\.stringValue)
        #expect(!labels.contains(copied))
    }
}
