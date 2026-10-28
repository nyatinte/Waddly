import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@Suite(.serialized) @MainActor struct SetupWizardImportFeedbackTests {
    enum NavigationAction: CaseIterable { case step, beginImport, close }

    @Test(arguments: NavigationAction.allCases)
    func navigationInvalidatesASuspendedImportFailure(action: NavigationAction) async throws {
        let state = SetupWizardFixture.State()
        let (started, signal) = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<PetImageSet?, Never>?
        let wizard = try SetupWizardFixture.makeWizard(state: state, preview: { _ in
            await withCheckedContinuation { continuation in
                pending = continuation
                signal.yield()
            }
        })
        defer { wizard.close(); signal.finish() }
        let task = wizard.importImage(from: URL(fileURLWithPath: "/pending.png"))
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        switch action {
        case .step: wizard.setStep(.monitoring)
        case .beginImport: wizard.beginCharacterImport()
        case .close: wizard.close()
        }
        pending?.resume(returning: nil)
        await task.value
        #expect(!wizard.didFailImport)
        #expect(state.announcements.isEmpty)
    }

    @Test(arguments: [true, false])
    func newerImportOwnsFeedbackWhenAnOlderFailureResumes(succeeds: Bool) async throws {
        let images = try SetupWizardFixture.sheetImages()
        let state = SetupWizardFixture.State()
        let (started, signal) = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<PetImageSet?, Never>?
        let wizard = try SetupWizardFixture.makeWizard(state: state, preview: { url in
            guard url.lastPathComponent == "pending.png" else { return succeeds ? images : nil }
            return await withCheckedContinuation { continuation in
                pending = continuation
                signal.yield()
            }
        }, confirmResult: true)
        defer { wizard.close(); signal.finish() }
        let older = wizard.importImage(from: URL(fileURLWithPath: "/pending.png"))
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        await wizard.importImage(from: URL(fileURLWithPath: "/newer.png")).value
        let announcements = state.announcements
        #expect(wizard.didFailImport == !succeeds)
        #expect(wizard.didRegisterPet == succeeds)
        #expect(announcements.count == (succeeds ? 0 : 1))
        pending?.resume(returning: nil)
        await older.value
        #expect(wizard.didFailImport == !succeeds)
        #expect(state.announcements == announcements)
        if succeeds {
            #expect(wizard.currentPetImages()[.idle].first === images[.idle].first)
        }
    }
}
