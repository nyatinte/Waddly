import AppKit
import Testing
@testable import WaddlyApp

@Suite(.serialized) @MainActor struct SetupWizardTests {
    @Test func imagePageDropTargetsHaveImportHandlers() throws {
        let wizard = try makeWizard()
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        let skip = try #require(descendants(of: content).compactMap { $0 as? NSButton }
            .first { $0.action == NSSelectorFromString("skipPrompt") })
        skip.performClick(nil)
        let targets = descendants(of: content).compactMap { $0 as? PetImageDropView }
            .filter { $0.registeredDraggedTypes.contains(.fileURL) }
        #expect(!targets.isEmpty)
        for target in targets {
            #expect(target.onDrop != nil)
        }
    }

    @Test(arguments: [AppLanguage.japanese, .english])
    func imagePageStatusFitsInsideItsContainer(language: AppLanguage) throws {
        let wizard = try makeWizard(language: language)
        defer { wizard.close() }
        let window = try #require(wizard.window)
        let content = try #require(window.contentView)
        let skip = try #require(descendants(of: content).compactMap { $0 as? NSButton }
            .first { $0.action == NSSelectorFromString("skipPrompt") })
        skip.performClick(nil)
        content.layoutSubtreeIfNeeded()
        let status = try #require(descendants(of: content).compactMap { $0 as? NSTextField }
            .first { $0.stringValue == wizard.localizedString(.setupImageRequired) })
        #expect(status.frame.height >= status.intrinsicContentSize.height)
        var ancestor = status.superview
        while let view = ancestor {
            let frame = status.convert(status.bounds, to: view)
            #expect(frame.minY >= view.bounds.minY - 1)
            #expect(frame.maxY <= view.bounds.maxY + 1)
            ancestor = view.superview
        }
    }

    @Test func imageRowsKeepTheirScrollViewAsAnInputTarget() throws {
        let wizard = try makeWizard()
        defer { wizard.close() }
        let row = PetImageCategoryRowView(
            category: .typing,
            images: (0 ..< 12).map { _ in NSImage(size: NSSize(width: 2, height: 2)) },
            localization: wizard.localization
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 138),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = row
        row.layoutSubtreeIfNeeded()
        let scroll = try #require(descendants(of: row).compactMap { $0 as? NSScrollView }.first)
        let point = scroll.convert(NSPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: row)
        let hit = try #require(row.hitTest(point))
        #expect(hit === scroll || hit.isDescendant(of: scroll))
    }

    @Test func wizardRequiresImagesButAllowsFinishingWithoutPermission() throws {
        let state = WizardState()
        let wizard = try makeWizard(hasImage: { state.hasImage }, onClose: { state.closed = true })
        defer { wizard.close() }
        let content = try #require(wizard.window?.contentView)
        func button(_ action: String) throws -> NSButton {
            try #require(descendants(of: content).compactMap { $0 as? NSButton }
                .first { $0.action == NSSelectorFromString(action) })
        }
        try button("skipPrompt").performClick(nil)
        #expect(try !button("goNext").isEnabled)
        try button("goNext").performClick(nil)
        #expect(descendants(of: content).compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == wizard.localizedString(.setupImageRequired) })
        state.hasImage = true
        wizard.renderCurrentStep()
        #expect(try button("goNext").isEnabled)
        try button("goNext").performClick(nil)
        #expect(descendants(of: content).compactMap { $0 as? NSTextField }
            .contains { $0.stringValue == wizard.localizedString(.setupPermissionRequired) })
        #expect(try button("goNext").isEnabled)
        #expect(try button("goNext").title == wizard.localizedString(.setupFinish))
        try button("goNext").performClick(nil)
        #expect(state.closed)
    }

    private func makeWizard(
        language: AppLanguage = .japanese,
        hasImage: @escaping @MainActor () -> Bool = { false },
        onClose: @escaping @MainActor () -> Void = {}
    ) throws -> SetupWizardController {
        _ = NSApplication.shared
        let name = "WaddlyTests.wizard.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = AppSettings(defaults: defaults)
        settings.appLanguage = language
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let resources = try #require(Bundle(url: root.appendingPathComponent("macos")))
        return SetupWizardController(
            localization: LocalizationController(settings: settings, resources: resources),
            onImportImage: { _ in false },
            hasCustomImage: hasImage,
            hasInputMonitoringPermission: { false },
            requestInputMonitoringPermission: { false },
            onClose: {
                defaults.removePersistentDomain(forName: name)
                onClose()
            }
        )
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    @MainActor private final class WizardState {
        var hasImage = false
        var closed = false
    }
}
