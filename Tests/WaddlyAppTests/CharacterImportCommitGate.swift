import Testing
@testable import WaddlyApp

@MainActor
final class CharacterImportCommitGate {
    private(set) var commitCount = 0
    private var outcomeContinuation: CheckedContinuation<CharacterCommitOutcome, Never>?

    func commit() async -> CharacterCommitOutcome {
        commitCount += 1
        guard commitCount == 1, outcomeContinuation == nil else {
            Issue.record("commit gate entered more than once")
            return .failed
        }
        return await withCheckedContinuation { outcomeContinuation = $0 }
    }

    func waitUntilEntered() async -> Bool {
        for _ in 0 ..< 500 {
            if commitCount > 0 {
                return true
            }
            await Task.yield()
        }
        return false
    }

    func resume(with outcome: CharacterCommitOutcome) {
        guard let outcomeContinuation else {
            Issue.record("commit gate resumed without a suspended commit")
            return
        }
        self.outcomeContinuation = nil
        outcomeContinuation.resume(returning: outcome)
    }
}
