import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Test @MainActor func petContextMenuOffersShareOnlyWhenThePetIsReady() throws {
    _ = NSApplication.shared
    let suiteName = "WaddlyTests.share-menu.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let app = AppDelegate(settings: AppSettings(defaults: defaults))
    app.buildMenu()
    let menu = app.makePetContextMenu()
    let share = try #require(menu.items.first { $0.action == #selector(AppDelegate.showPetShare) })

    #expect(share.title == app.localizedString(.shareMenu))
    #expect(menu.items.first?.action == #selector(AppDelegate.showPetShare))
    #expect(menu.items.dropFirst().first?.isSeparatorItem == true)
    #expect(!app.validateMenuItem(share))
    app.importedImages = PetImageSet(Dictionary(uniqueKeysWithValues: PetImageCategory.allCases.map {
        ($0, [NSImage(size: NSSize(width: 2, height: 2))])
    }))
    #expect(app.validateMenuItem(share))
}
