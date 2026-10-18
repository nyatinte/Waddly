import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

/// The store must read the app's current image directory, not the path it happened to see when the
/// lazy store was first built. A test that touches image state before assigning its isolated
/// directory would otherwise leave the store bound to the production Application Support path and
/// write (or sweep) the user's frames there.
@Test @MainActor func reboundDirectoryWinsOverTheDirectoryAtFirstStoreTouch() async throws {
    _ = NSApplication.shared
    let domain = "WaddlyTests.directory-binding.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let sentinel = FileManager.default.temporaryDirectory
        .appendingPathComponent("WaddlySentinel-\(UUID().uuidString)", isDirectory: true)
    let active = FileManager.default.temporaryDirectory
        .appendingPathComponent("WaddlyActive-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: sentinel)
        try? FileManager.default.removeItem(at: active)
    }

    let app = makeTestApp(settings: AppSettings(defaults: defaults))
    defer {
        app.imageStore.beginShutdown()
        app.animationController.shutdown()
    }
    app.settings.registerDefaults()
    app.buildPanel()
    // First touch happens while only the sentinel is known, so the store exists already.
    app.petImagesDirectoryURL = sentinel
    _ = app.petImages
    try #require(app.imageStore.directory == sentinel)

    // Rebinding must take effect for the next transaction instead of staying on the sentinel.
    app.petImagesDirectoryURL = active
    try #require(app.imageStore.directory == active)

    let sheet = try #require(try PetSpriteSheetImporter.frames(from: Data(contentsOf: exampleSheetURL())))
    try await app.persistPetImages(sheet)
    await app.loadSavedPetImage()

    let manifest = try PetImageStorage(directory: active).readManifest()
    #expect(manifest != nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: active.path).count > 1)
    let sentinelEntries = (try? FileManager.default.contentsOfDirectory(atPath: sentinel.path)) ?? []
    #expect(sentinelEntries.isEmpty)
}

private func exampleSheetURL() throws -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("assets/examples/nyatinte-bot-3x3.png")
}
