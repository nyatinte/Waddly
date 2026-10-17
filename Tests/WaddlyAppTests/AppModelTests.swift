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

@Test func promptFilesMatchTheReadmeCopy() throws {
    // The extractor rejects missing, unclosed, repeated, and empty fences, so a broken fence
    // fails the comparison below instead of passing against an empty block.
    #expect(textFenceBody(in: "no fence") == nil)
    #expect(textFenceBody(in: "```text\n```") == nil)
    #expect(textFenceBody(in: "```text\n\n```") == nil)
    #expect(textFenceBody(in: "```text\nunclosed") == nil)
    #expect(textFenceBody(in: "```text\na\n```\n```text\nb\n```") == nil)
    #expect(textFenceBody(in: "```text\nhello\n```") == "hello")

    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    for (language, readme) in [("en", "README.md"), ("ja", "README.ja.md")] {
        let prompt = try String(contentsOf: root.appendingPathComponent("prompts/\(language).md"), encoding: .utf8)
        let readmeCopy = try String(contentsOf: root.appendingPathComponent(readme), encoding: .utf8)
        let promptBody = try #require(textFenceBody(in: prompt), "prompts/\(language).md has no usable text fence")
        let readmeBody = try #require(textFenceBody(in: readmeCopy), "\(readme) has no usable text fence")
        #expect(promptBody == readmeBody, "\(readme) is stale against prompts/\(language).md")
    }
}

/// Extracts the body of the single ```text fenced block, or `nil` when the fence is missing,
/// unclosed, repeated, or empty.
private func textFenceBody(in markdown: String) -> String? {
    let marker = "```text\n"
    guard let start = markdown.range(of: marker),
          let end = markdown[start.upperBound...].range(of: "\n```"),
          !markdown[start.upperBound ..< end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          markdown.range(of: marker, range: start.upperBound ..< markdown.endIndex) == nil
    else {
        return nil
    }
    return String(markdown[start.upperBound ..< end.lowerBound])
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

@Test func movingAnElementPreservesTheRequestedOrder() {
    let elements = ["first", "second", "third"]

    #expect(moving(elements, from: 0, to: 2) == ["second", "third", "first"])
    #expect(moving(elements, from: 2, to: 0) == ["third", "first", "second"])
    #expect(moving(["only"], from: 1, to: 0) == nil)
}
