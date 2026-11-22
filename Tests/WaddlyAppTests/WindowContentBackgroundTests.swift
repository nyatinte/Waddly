import AppKit
import Testing
@testable import WaddlyApp

@Test @MainActor func windowContentMaterialUsesSystemBehindWindowBlending() {
    let material = makeWindowContentMaterial()
    #expect(material.material == .underWindowBackground)
    #expect(material.blendingMode == .behindWindow)
    #expect(material.state == .followsWindowActiveState)
}

@Test @MainActor func eachCharacterImportHostOwnsOneWindowBackground() throws {
    guard #available(macOS 26.0, *) else { return }
    let wizard = try SetupWizardFixture.makeWizard()
    defer { wizard.close() }
    wizard.beginCharacterImport()
    let setupRoot = try #require(wizard.window?.contentView)
    CaptureHarness.settle(setupRoot)
    #expect(windowMaterials(in: setupRoot).count == 1)

    let model = CharacterImportModel(currentImages: { .init() }, commit: { _ in .committed })
    let controller = CharacterImportWindowController(
        model: model,
        localization: wizard.localization,
        presenter: .invisible,
        onClose: {}
    )
    defer { controller.close() }
    controller.focus()
    let changeRoot = try #require(controller.window?.contentView)
    CaptureHarness.settle(changeRoot)
    #expect(windowMaterials(in: changeRoot).count == 1)
}

@MainActor private func windowMaterials(in root: NSView) -> [NSVisualEffectView] {
    SetupWizardFixture.descendants(of: root).compactMap { $0 as? NSVisualEffectView }
        .filter { $0.material == .underWindowBackground && $0.blendingMode == .behindWindow }
}
