import Testing
@testable import WaddlyApp

@MainActor
final class CharacterImportCommitGate {
    private(set) var isEntered = false
    private var outcomeContinuation: CheckedContinuation<CharacterCommitOutcome, Never>?

    func commit() async -> CharacterCommitOutcome {
        isEntered = true
        return await withCheckedContinuation { outcomeContinuation = $0 }
    }

    func waitUntilEntered() async -> Bool {
        for _ in 0 ..< 500 {
            if isEntered {
                return true
            }
            await Task.yield()
        }
        return false
    }

    func resume(with outcome: CharacterCommitOutcome) {
        outcomeContinuation?.resume(returning: outcome)
        outcomeContinuation = nil
    }
}
