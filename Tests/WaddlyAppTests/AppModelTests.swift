import AppKit
import Foundation
import Testing
@testable import WaddlyApp

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
        #expect(dockItem.isEnabled == showMenuBar)
        #expect(menuBarItem.isEnabled == showDock)
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
        onImportImage: { _ in false },
        hasCustomImage: { false },
        hasInputMonitoringPermission: { false },
        requestInputMonitoringPermission: { false },
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

@Test func movingAnElementPreservesTheRequestedOrder() {
    let elements = ["first", "second", "third"]

    #expect(moving(elements, from: 0, to: 2) == ["second", "third", "first"])
    #expect(moving(elements, from: 2, to: 0) == ["third", "first", "second"])
    #expect(moving(["only"], from: 1, to: 0) == nil)
}
