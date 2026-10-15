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
        wizard.importImage(from: url)
        try await Fixture.waitUntil { wizard.hasImage }
        #expect(wizard.didRegisterPet)
        #expect(wizard.importedFileName == url.lastPathComponent)
        #expect(wizard.previewPane.hasPet)
    }

    @Test func unreadableSheetLeavesThePreviousSetAlone() async throws {
        let wizard = try Fixture.makeWizard(previewResult: nil)
        defer { wizard.close() }
        try wizard.importImage(from: Fixture.sheetURL())
        try await Task.sleep(for: .milliseconds(50))
        #expect(!wizard.hasImage)
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
}
