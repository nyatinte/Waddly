import AppKit
import os
import Testing
@testable import WaddlyApp
import WaddlyCore

/// One dialog wired for a test: English copy, a stub export, and the view the user would see.
@MainActor
private struct ShareFixture {
    let suiteName: String
    let localization: LocalizationController
    let controller: PetShareWindowController
    let view: PetShareDialogView

    static func make(effects: PetShareEffects) throws -> ShareFixture {
        _ = NSApplication.shared
        let suiteName = "WaddlyTests.share-flow.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
        let localization = LocalizationController(
            settings: AppSettings(defaults: defaults),
            resources: resources
        )
        let images = try SetupWizardFixture.sheetImages()
        let controller = PetShareWindowController(
            images: images,
            localization: localization,
            effects: effects
        )
        let view = try #require(controller.window?.contentView as? PetShareDialogView)
        return ShareFixture(suiteName: suiteName, localization: localization, controller: controller, view: view)
    }

    func button(_ identifier: String) throws -> NSButton {
        try #require(SetupWizardFixture.descendants(of: view).compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == identifier })
    }

    func label(_ identifier: String) throws -> NSTextField {
        try #require(SetupWizardFixture.descendants(of: view).compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == identifier })
    }

    func cleanUp() {
        controller.close()
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}

/// Yields the main actor while polling, so the controller's detached export can make progress.
@MainActor
private func waitFor(_ condition: () -> Bool, within seconds: TimeInterval = 5) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

private func writeStub(_ url: URL) throws {
    try Data("movie".utf8).write(to: url)
}

@Test @MainActor func aSecondGenerationRequestDoesNotStartAnotherExport() async throws {
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let release = DispatchSemaphore(value: 0)
    let fixture = try ShareFixture.make(effects: PetShareEffects(writeMovie: { _, url, _ in
        calls.withLock { $0 += 1 }
        // Hold the first export open so a second request would overlap it if the guard were missing.
        guard release.wait(timeout: .now() + 30) == .success else { throw PetShareExportError.timedOut }
        try writeStub(url)
    }))
    defer { fixture.cleanUp() }
    let postButton = try fixture.button("share.postButton")

    fixture.controller.prepareAssets()
    #expect(await waitFor { calls.withLock { $0 } == 1 })
    #expect(fixture.controller.status == .working)
    #expect(!postButton.isEnabled)

    fixture.controller.prepareAssets()
    release.signal()
    #expect(await waitFor { fixture.controller.status == .ready })
    #expect(postButton.isEnabled)

    fixture.controller.prepareAssets()
    try await Task.sleep(for: .milliseconds(50))
    #expect(calls.withLock { $0 } == 1)
}

@Test @MainActor func retryingAfterAFailedGenerationShowsTheAssets() async throws {
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let fixture = try ShareFixture.make(effects: PetShareEffects(writeMovie: { _, url, _ in
        let attempt = calls.withLock { $0 += 1; return $0 }
        guard attempt > 1 else { throw PetShareExportError.timedOut }
        try writeStub(url)
    }))
    defer { fixture.cleanUp() }

    fixture.controller.prepareAssets()
    #expect(await waitFor { fixture.controller.status == .failed })
    let failure = try fixture.label("share.failure")
    let retry = try fixture.button("share.retry")
    #expect(!failure.isHiddenOrHasHiddenAncestor)
    #expect(failure.stringValue == fixture.localization.string(for: .shareError))

    try sendTestAction(retry)
    #expect(await waitFor { fixture.controller.status == .ready })
    #expect(calls.withLock { $0 } == 2)
    #expect(failure.isHiddenOrHasHiddenAncestor)
}

@Test @MainActor func copyingReportsWhatThePasteboardDidNextToTheAsset() async throws {
    let copiedImages = OSAllocatedUnfairLock(initialState: [Data]())
    let fixture = try ShareFixture.make(effects: PetShareEffects(
        writeMovie: { _, url, _ in try writeStub(url) },
        copyImage: { data in
            copiedImages.withLock { $0.append(data) }
            return true
        },
        copyMovie: { _, _ in false }
    ))
    defer { fixture.cleanUp() }
    fixture.controller.prepareAssets()
    #expect(await waitFor { fixture.controller.status == .ready })

    let imageStatus = try fixture.label("share.imageStatus")
    let videoStatus = try fixture.label("share.videoStatus")
    try sendTestAction(fixture.button("share.copyImage"))
    #expect(imageStatus.stringValue == fixture.localization.string(for: .shareCopiedImage))
    #expect(videoStatus.stringValue.isEmpty)
    #expect(copiedImages.withLock { $0.first } != nil)

    try sendTestAction(fixture.button("share.copyVideo"))
    #expect(videoStatus.stringValue == fixture.localization.string(for: .shareCopyFailed))
    #expect(imageStatus.stringValue == fixture.localization.string(for: .shareCopiedImage))
}

@Test @MainActor func sharePostAndRetryButtonsShowHoverStates() async throws {
    let fixture = try ShareFixture.make(effects: PetShareEffects(writeMovie: { _, url, _ in try writeStub(url) }))
    defer { fixture.cleanUp() }
    fixture.controller.prepareAssets()
    #expect(await waitFor { fixture.controller.status == .ready })

    let post = try #require(fixture.button("share.postButton") as? ShareActionButton)
    fixture.view.layoutSubtreeIfNeeded()
    #expect(post.isEnabled)
    #expect(post.frame.height == LayoutMetrics.actionHeight)
    #expect(post.target != nil)
    #expect(post.action != nil)
    #expect(post.focusRingType != .none)
    #expect(post.accessibilityLabel() == fixture.localization.string(for: .shareXCreate))
    #expect(post.accessibilityHelp() == fixture.localization.string(for: .shareXHelp))
    try assertHoverStates(post)

    fixture.view.showFailure()
    fixture.view.layoutSubtreeIfNeeded()
    let retry = try #require(fixture.button("share.retry") as? ShareActionButton)
    #expect(retry.isEnabled)
    #expect(retry.frame.height == LayoutMetrics.actionHeight)
    #expect(retry.target != nil)
    #expect(retry.action != nil)
    #expect(retry.focusRingType != .none)
    try assertHoverStates(retry)

    fixture.localization.changeLanguage(.japanese)
    fixture.view.refreshLocalization()
    #expect(post.accessibilityHelp() == fixture.localization.string(for: .shareXHelp))
    #expect(post.accessibilityLabel() == fixture.localization.string(for: .shareXCreate))
}

@MainActor private func assertHoverStates(_ button: ShareActionButton) throws {
    let resting = try #require(button.layer?.backgroundColor)
    let frame = button.frame
    button.setHovered(true)
    #expect(button.isHovered)
    #expect(button.layer?.backgroundColor != resting)
    let hovered = try #require(button.layer?.backgroundColor)
    button.highlight(true)
    #expect(button.layer?.backgroundColor != hovered)
    button.highlight(false)
    #expect(button.layer?.backgroundColor == hovered)
    button.setHovered(false)
    #expect(!button.isHovered)
    #expect(button.layer?.backgroundColor == resting)
    #expect(button.frame == frame)
    button.setHovered(true)
    button.isEnabled = false
    #expect(!button.isHovered)
    #expect(button.layer?.backgroundColor != resting)
    button.isEnabled = true
}

@Test @MainActor func copyingVideoPublishesAFileThatOutlivesTemporaryExportAssets() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WaddlyTests.share-paste.\(UUID().uuidString)", isDirectory: true)
    let publishedURL = OSAllocatedUnfairLock<URL?>(initialState: nil)
    let copiedURL = OSAllocatedUnfairLock<URL?>(initialState: nil)
    let fixture = try ShareFixture.make(effects: PetShareEffects(
        writeMovie: { _, url, _ in try writeStub(url) },
        publishMovie: { data, name in
            let url = directory.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url)
                publishedURL.withLock { $0 = url }
                return url
            } catch {
                return nil
            }
        },
        copyMovie: { _, url in
            copiedURL.withLock { $0 = url }
            return true
        }
    ))
    fixture.controller.prepareAssets()
    #expect(await waitFor { fixture.controller.status == .ready })

    try sendTestAction(fixture.button("share.copyVideo"))
    let outputURL = try #require(publishedURL.withLock { $0 })
    #expect(outputURL.lastPathComponent == "WaddlyShare.mp4")
    #expect(copiedURL.withLock { $0 } == outputURL)
    fixture.cleanUp()
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    try FileManager.default.removeItem(at: directory)
}

@Test @MainActor func aComposerThatCannotOpenIsReportedInline() async throws {
    let opens = OSAllocatedUnfairLock(initialState: false)
    let fixture = try ShareFixture.make(effects: PetShareEffects(
        writeMovie: { _, url, _ in try writeStub(url) },
        openURL: { _ in opens.withLock { $0 } }
    ))
    defer { fixture.cleanUp() }
    fixture.controller.prepareAssets()
    #expect(await waitFor { fixture.controller.status == .ready })
    let postStatus = try fixture.label("share.postStatus")

    try sendTestAction(fixture.button("share.postButton"))
    #expect(postStatus.stringValue == fixture.localization.string(for: .shareOpenXFailed))

    opens.withLock { $0 = true }
    try sendTestAction(fixture.button("share.postButton"))
    #expect(postStatus.stringValue.isEmpty)
}

@Test @MainActor func shareActionsReportHoverWithoutMovingTheLayout() throws {
    _ = NSApplication.shared
    let suiteName = "WaddlyTests.share-hover.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let resources = try #require(Bundle(url: SetupWizardFixture.root().appendingPathComponent("macos")))
    let view = PetShareDialogView(
        localization: LocalizationController(settings: AppSettings(defaults: defaults), resources: resources)
    )
    let copy = try #require(SetupWizardFixture.descendants(of: view).compactMap { $0 as? ShareActionButton }
        .first { $0.identifier?.rawValue == "share.copyVideo" })
    view.layoutSubtreeIfNeeded()
    let resting = copy.layer?.backgroundColor
    let frame = copy.frame
    #expect(copy.frame.height == LayoutMetrics.actionHeight)

    copy.setHovered(true)
    #expect(copy.isHovered)
    #expect(copy.layer?.backgroundColor != resting)
    copy.setHovered(false)
    #expect(copy.layer?.backgroundColor == resting)

    copy.isEnabled = false
    copy.setHovered(true)
    #expect(!copy.isHovered)
    #expect(copy.layer?.backgroundColor != resting)
    copy.isEnabled = true

    #expect(copy.focusRingType != .none)
    view.showCopyResult("Copied", failed: false, for: .video)
    view.layoutSubtreeIfNeeded()
    #expect(copy.frame == frame)
}
