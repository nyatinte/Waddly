import Foundation

@MainActor
final class AnimationCancellation {
    private var cancel: (() -> Void)?

    init(_ cancel: @escaping () -> Void) {
        self.cancel = cancel
    }

    func invalidate() {
        cancel?()
        cancel = nil
    }
}

@MainActor
protocol AnimationScheduling {
    var now: TimeInterval { get }
    func schedule(
        after interval: TimeInterval,
        repeats: Bool,
        action: @escaping @MainActor () -> Void
    ) -> AnimationCancellation
}

@MainActor
final class ContinuousAnimationScheduler: AnimationScheduling {
    private let clock = ContinuousClock()
    private let origin = ContinuousClock.now

    var now: TimeInterval {
        let duration = origin.duration(to: clock.now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    func schedule(
        after interval: TimeInterval,
        repeats: Bool,
        action: @escaping @MainActor () -> Void
    ) -> AnimationCancellation {
        let clock = clock
        let duration = Duration.seconds(interval)
        let firstDeadline = clock.now.advanced(by: duration)
        let task = Task { @MainActor in
            var deadline = firstDeadline
            do {
                repeat {
                    try await clock.sleep(until: deadline)
                    try Task.checkCancellation()
                    action()
                    // Skip missed ticks, as a run-loop timer does, rather than
                    // replaying frames after a busy main actor or system sleep.
                    deadline = deadline.advanced(by: duration)
                    if deadline <= clock.now {
                        deadline = clock.now.advanced(by: duration)
                    }
                } while repeats && !Task.isCancelled
            } catch is CancellationError {
                // Cancellation is the normal pause/replacement/shutdown path.
            } catch {
                assertionFailure("Animation clock failed: \(error)")
            }
        }
        return AnimationCancellation { task.cancel() }
    }
}
