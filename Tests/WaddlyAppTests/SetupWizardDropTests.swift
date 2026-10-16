import AppKit
import Testing
@testable import WaddlyApp

@Suite(.serialized) @MainActor struct SetupWizardDropTests {
    @Test func hostedWizardRetainsWindowWideAndPreviewDropTargets() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView as? PetImageDropView)
        #expect(content.onDrop != nil)
        #expect(content.registeredDraggedTypes.contains(.fileURL))
        #expect(wizard.previewPane.onDrop != nil)
        #expect(wizard.previewPane.registeredDraggedTypes.contains(.fileURL))
    }
}
