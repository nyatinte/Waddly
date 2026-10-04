import AppKit
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

    let copy = copyMenuTree(original)
    let copiedItem = copy.items[0].submenu?.items[0]

    #expect(copy !== original)
    #expect(copy.items[0] !== original.items[0])
    #expect(copy.items[0].submenu !== original.items[0].submenu)
    #expect(copiedItem?.title == item.title)
    #expect(copiedItem?.tag == item.tag)
    #expect(copiedItem?.state == item.state)
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
