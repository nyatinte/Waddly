import AppKit
import Foundation
import Testing
@testable import WaddlyApp
import WaddlyCore

@Test func petPhasesChangeAtTheirExistingThresholds() {
    #expect(PetPhase.after(0) == .typing)
    #expect(PetPhase.after(2.5) == .idle)
    #expect(PetPhase.after(25) == .sleeping)
    #expect(PetPhase.after(325) == .frozen)
}

@Test func typingMotionUsesTheConfiguredAmplitudes() {
    #expect(TypingMotion.off.amplitude == 0)
    #expect(TypingMotion.weak.amplitude == 5)
    #expect(TypingMotion.strong.amplitude == 10)
}

@Test func appLanguageSelectsJapaneseAndDefaultsOtherLanguagesToEnglish() {
    #expect(AppLanguage.detectedLocalization(["ja-JP", "en"]) == "ja")
    #expect(AppLanguage.detectedLocalization(["en-US", "ja"]) == "en")
    #expect(AppLanguage.detectedLocalization(["fr-FR"]) == "en")
    #expect(AppLanguage.japanese.localization == "ja")
    #expect(AppLanguage.english.localization == "en")
    #expect(AppLanguage.system.localization == AppLanguage.detectedLocalization(Bundle.main.preferredLocalizations))
}

@Test func localizationControllerUsesItsInjectedSettings() throws {
    let suiteName = "WaddlyTests.localization.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let controller = LocalizationController(settings: AppSettings(defaults: defaults))
    let standardLanguage = AppSettings.standard.appLanguage

    #expect(controller.selectedLanguage == .system)
    controller.changeLanguage(.japanese)
    #expect(controller.selectedLanguage == .japanese)
    #expect(controller.activeLocalization == "ja")
    controller.changeLanguage(.english)
    #expect(controller.activeLocalization == "en")
    #expect(AppSettings.standard.appLanguage == standardLanguage)
}

@Test @MainActor func copiedMenusHaveIndependentItemsAndPreserveNestedCommandsAndState() {
    let original = NSMenu(title: "Original")
    let submenu = NSMenu(title: "Options")
    let item = NSMenuItem(title: "English", action: nil, keyEquivalent: "")
    item.tag = AppLanguage.english.rawValue
    item.state = .on
    submenu.addItem(item)
    let parent = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
    parent.submenu = submenu
    original.addItem(parent)
    original.addItem(.separator())

    let copy = copyMenuTree(original)
    let copiedItem = copy.items[0].submenu?.items[0]

    #expect(copy !== original)
    #expect(copy.items[0] !== original.items[0])
    #expect(copy.items[0].submenu !== original.items[0].submenu)
    #expect(copiedItem?.title == item.title)
    #expect(copiedItem?.tag == item.tag)
    #expect(copiedItem?.state == item.state)
    #expect(copy.items[1].isSeparatorItem)
}

@Test @MainActor func copiedMenuSelectionUpdatesBothMenuTrees() {
    let action = #selector(NSApplication.terminate(_:))
    let source = makeSelectionMenu(action: action)
    let copy = copyMenuTree(source)

    synchronizeMenuSelection(in: [source, copy], action: action, selectedTag: 320)

    #expect(source.items.map(\.state) == [.off, .off, .on])
    #expect(copy.items.map(\.state) == [.off, .off, .on])
}

@Test @MainActor func presenceMenuSelectionAndEnabledStateReflectEveryVisibleSurfaceCombination() {
    let cases = [(true, true), (true, false), (false, true), (false, false)]

    for (showDock, showMenuBar) in cases {
        let dockItem = NSMenuItem()
        let menuBarItem = NSMenuItem()
        updatePresenceMenuItems(
            dockItem: dockItem,
            menuBarItem: menuBarItem,
            showInDock: showDock,
            showInMenuBar: showMenuBar
        )
        #expect(dockItem.state == (showDock ? .on : .off))
        #expect(menuBarItem.state == (showMenuBar ? .on : .off))
        // The switch that would leave nothing else on is held back, and an option that is already
        // off stays available.
        #expect(dockItem.isEnabled == (showMenuBar || !showDock))
        #expect(menuBarItem.isEnabled == (showDock || !showMenuBar))
        // Whatever the combination, one way back into the app stays available.
        #expect(dockItem.isEnabled || menuBarItem.isEnabled)
    }
}

@Test func pauseMenuTitleFollowsThePausedState() {
    #expect(pauseMenuTitleKey(isPaused: true) == .menuResume)
    #expect(pauseMenuTitleKey(isPaused: false) == .menuPause)
}

@MainActor private func makeSelectionMenu(action: Selector) -> NSMenu {
    let menu = NSMenu()
    for size in [180, 240, 320] {
        let item = NSMenuItem(title: "\(size)", action: action, keyEquivalent: "")
        item.tag = size
        item.state = size == 180 ? .on : .off
        menu.addItem(item)
    }
    return menu
}

@Test func localizationFilesUseLiteralCharactersInsteadOfUnicodeEscapes() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    for language in ["en", "ja"] {
        let url = root.appendingPathComponent("macos/\(language).lproj/Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        // Foundation reads these files as old-style plists, which do not accept lowercase \u escapes.
        #expect(!text.contains("\\u"), "\(language).lproj contains a \\u escape")
    }
}

@Test @MainActor func setupWizardPromptTracksTheInjectedLanguage() throws {
    _ = NSApplication.shared
    let suiteName = "WaddlyTests.prompt.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let resourcesURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let promptsURL = resourcesURL.appendingPathComponent("prompts", isDirectory: true)
    try FileManager.default.createDirectory(at: promptsURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: resourcesURL) }
    try Data("```text\nこんにちは\n```".utf8).write(to: promptsURL.appendingPathComponent("ja.md"))
    try Data("```text\nHello\n```".utf8).write(to: promptsURL.appendingPathComponent("en.md"))

    let localization = LocalizationController(settings: AppSettings(defaults: defaults))
    localization.changeLanguage(.japanese)
    let wizard = SetupWizardController(
        localization: localization,
        promptResourcesURL: resourcesURL,
        onPreviewImage: { _ in nil },
        onConfirmImage: { _ in false },
        currentPetImages: { PetImageSet() },
        permission: PermissionService(
            hasPermission: { false },
            isReceivingKeys: { false },
            requestAccess: { false },
            restartTap: {}
        ),
        onClose: {}
    )

    #expect(wizard.prompt == "こんにちは")
    localization.changeLanguage(.english)
    #expect(wizard.prompt == "Hello")
}

@Test func enterDetectionRecognizesBothMacEnterKeys() {
    #expect(KeyboardMonitor.isEnterKeyCode(36))
    #expect(KeyboardMonitor.isEnterKeyCode(76))
    #expect(!KeyboardMonitor.isEnterKeyCode(0))
}

@Test @MainActor func animationSettingsModelForwardsEditorActionsAndTracksThumbnails() throws {
    let suiteName = "WaddlyTests.animationSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let localization = LocalizationController(settings: AppSettings(defaults: defaults))
    let first = NSImage(size: NSSize(width: 2, height: 2))
    let second = NSImage(size: NSSize(width: 2, height: 2))
    let model = AnimationSettingsModel(
        thumbnailsByCategory: [.idle: [AnimationSettingsThumbnail(image: first)]],
        localization: localization
    )

    var added: PetImageCategory?
    var dropped: (PetImageCategory, [URL])?
    var removed: (PetImageCategory, Int)?
    var movedCategory: PetImageCategory?
    var movedFrom: Int?
    var movedTo: Int?
    model.onAdd = { added = $0 }
    model.onDrop = { dropped = ($0, $1) }
    model.onRemove = { removed = ($0, $1) }
    model.onMove = { category, source, destination in
        movedCategory = category
        movedFrom = source
        movedTo = destination
    }

    #expect(model.thumbnails(for: .idle).map(\.id) == [ObjectIdentifier(first)])
    model.add(.typing)
    model.drop([URL(fileURLWithPath: "/tmp/pet.png")], on: .sleep)
    model.remove(at: 2, from: .idle)
    model.move(from: 1, to: 3, in: .enter)
    #expect(added == .typing)
    #expect(dropped?.0 == .sleep)
    #expect(dropped?.1.map(\.lastPathComponent) == ["pet.png"])
    #expect(removed?.0 == .idle && removed?.1 == 2)
    #expect(movedCategory == .enter && movedFrom == 1 && movedTo == 3)

    model.setThumbnails([.idle: [AnimationSettingsThumbnail(image: second)]])
    #expect(model.thumbnails(for: .idle).map(\.id) == [ObjectIdentifier(second)])
}

/// The editor model must not retain itself once the app drops it: the callbacks AppDelegate wires
/// capture `self` weakly, and the model holds no self-reference. Immediate NSHostingView release is
/// a framework concern and is reported separately, not asserted here.
@Test @MainActor func animationSettingsModelDeallocatesWithoutASelfRetain() throws {
    let suiteName = "WaddlyTests.animationSettingsRelease.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let localization = LocalizationController(settings: AppSettings(defaults: defaults))
    weak var released: AnimationSettingsModel?
    autoreleasepool {
        let model = AnimationSettingsModel(thumbnailsByCategory: [:], localization: localization)
        model.onAdd = { _ in }
        released = model
    }
    #expect(released == nil)
}
