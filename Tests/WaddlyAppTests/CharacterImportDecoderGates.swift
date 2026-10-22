import AppKit
import Testing
@testable import WaddlyApp

/// Startup observation is bounded; release results are latched so a late-starting operation still
/// completes instead of suspending after the test's release call. Each gate accepts one operation.
@MainActor
final class SheetLoadGate {
    private var didStart = false
    private var continuation: CheckedContinuation<CharacterSheetLoadOutcome, Never>?
    private var releasedOutcome: CharacterSheetLoadOutcome?
    private let outcome: CharacterSheetLoadOutcome

    init(outcome: CharacterSheetLoadOutcome) {
        self.outcome = outcome
    }

    func load() async -> CharacterSheetLoadOutcome {
        guard !didStart else {
            Issue.record("sheet load gate started more than once")
            return .invalid(.notPNG)
        }
        didStart = true
        if let releasedOutcome {
            return releasedOutcome
        }
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async -> Bool {
        await waitForBoundedStartupObservation { didStart }
    }

    func release() {
        guard releasedOutcome == nil else {
            Issue.record("sheet load gate released more than once")
            return
        }
        releasedOutcome = outcome
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: outcome)
    }
}

@MainActor
final class CharacterCommitOutcomeGate {
    private var didStart = false
    private var continuation: CheckedContinuation<CharacterCommitOutcome, Never>?
    private var releasedOutcome: CharacterCommitOutcome?

    func commit() async -> CharacterCommitOutcome {
        guard !didStart else {
            Issue.record("character commit gate started more than once")
            return .failed
        }
        didStart = true
        if let releasedOutcome {
            return releasedOutcome
        }
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async -> Bool {
        await waitForBoundedStartupObservation { didStart }
    }

    func release(_ outcome: CharacterCommitOutcome) {
        guard releasedOutcome == nil else {
            Issue.record("character commit gate released more than once")
            return
        }
        releasedOutcome = outcome
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: outcome)
    }
}

@MainActor
private func waitForBoundedStartupObservation(_ isStarted: () -> Bool) async -> Bool {
    for _ in 0 ..< 500 where !isStarted() {
        await Task.yield()
    }
    return isStarted()
}
