import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// Where a PNG can be dropped. Split from the main suite so neither file grows past the limit.
@Suite(.serialized) @MainActor struct SetupWizardDropTests {
    @Test func welcomeStepOffersImportTargetsWithHandlers() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        let panes = Fixture.descendants(of: content).compactMap { $0 as? SetupPreviewPane }
        #expect(!panes.isEmpty)
        let targets = Fixture.descendants(of: content).compactMap { $0 as? PetImageDropView }
            .filter { $0.registeredDraggedTypes.contains(.fileURL) }
        #expect(!targets.isEmpty)
        for target in targets {
            #expect(target.onDrop != nil)
        }
    }

    /// The hint offers the whole window, so the only drop targets may be the window itself and the
    /// preview pane. Anything else in the left column would swallow the drop before it arrived.
    @Test func theWholeWindowAcceptsADroppedPNG() throws {
        let wizard = try Fixture.makeWizard()
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        let window = try #require(content as? PetImageDropView)
        #expect(window.onDrop != nil)
        let pane = try #require(
            Fixture.descendants(of: content).compactMap { $0 as? SetupPreviewPane }.first
        )
        let elsewhere = Fixture.descendants(of: content).compactMap { $0 as? PetImageDropView }
            .filter { $0 !== window && !$0.isDescendant(of: pane) }
        #expect(elsewhere.isEmpty)
    }
}
