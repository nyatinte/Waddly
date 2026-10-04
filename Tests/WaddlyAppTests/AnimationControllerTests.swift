import AppKit
import Testing
@testable import WaddlyApp
import WaddlyCore

@MainActor
private final class ManualAnimationScheduler: AnimationScheduling {
    private struct Job {
        let id: UUID
        var deadline: TimeInterval
        let interval: TimeInterval?
        let action: @MainActor () -> Void
    }

    var now: TimeInterval = 0
    private var jobs: [Job] = []
    private(set) var cancelledActions: [@MainActor () -> Void] = []
    var pendingCount: Int {
        jobs.count
    }

    func schedule(
        after interval: TimeInterval,
        repeats: Bool,
        action: @escaping @MainActor () -> Void
    ) -> AnimationCancellation {
        let id = UUID()
        jobs.append(Job(id: id, deadline: now + interval, interval: repeats ? interval : nil, action: action))
        return AnimationCancellation { [weak self] in
            guard let self else { return }
            cancelledActions += jobs.filter { $0.id == id }.map(\.action)
            jobs.removeAll { $0.id == id }
        }
    }

    func advance(by interval: TimeInterval) {
        let target = now + interval
        while let index = jobs.indices.min(by: { jobs[$0].deadline < jobs[$1].deadline }) {
            guard jobs[index].deadline <= target else { break }
            let job = jobs.remove(at: index)
            now = job.deadline
            if let interval = job.interval {
                jobs.append(Job(id: job.id, deadline: now + interval, interval: interval, action: job.action))
            }
            job.action()
        }
        now = target
    }

    func fireCancelledActions() {
        let actions = cancelledActions
        cancelledActions.removeAll()
        actions.forEach { $0() }
    }
}

@MainActor
private final class AnimationFixture {
    let scheduler = ManualAnimationScheduler()
    let view = NSImageView()
    var images = PetImageSet(Dictionary(uniqueKeysWithValues: PetImageCategory.allCases.map {
        ($0, [NSImage(size: NSSize(width: 1, height: 1)), NSImage(size: NSSize(width: 2, height: 2))])
    }))
    lazy var controller = PetAnimationController(
        petView: view,
        petImages: { [weak self] in self?.images ?? PetImageSet() },
        hasCompletePetImageSet: { [weak self] in self?.images.isComplete ?? false },
        typingMotion: { .off },
        isBreathingEnabled: { false },
        scheduler: scheduler,
        blinkDelay: { 4 }
    )
}

@Test @MainActor func animationAdvancesThroughAllPhasesWithoutWaiting() {
    let fixture = AnimationFixture()
    let controller = fixture.controller
    controller.start()
    controller.handleKeyDown(isEnter: false)
    #expect(controller.currentPhase == .typing)
    fixture.scheduler.advance(by: 2.5)
    #expect(controller.currentPhase == .idle)
    #expect(fixture.view.image === fixture.images[.idle][0])
    fixture.scheduler.advance(by: 22.5)
    #expect(controller.currentPhase == .sleeping)
    #expect(fixture.view.image === fixture.images[.sleep][0])
    fixture.scheduler.advance(by: 1.5)
    #expect(fixture.view.image === fixture.images[.sleep][1])
    fixture.scheduler.advance(by: 298.5)
    #expect(controller.currentPhase == .frozen)
    #expect(fixture.view.image === fixture.images[.sleep][1])
    #expect(fixture.scheduler.pendingCount == 0)
}

@Test @MainActor func blinkAndEnterFramesUseTheirExistingCadence() {
    let fixture = AnimationFixture()
    fixture.controller.start()
    fixture.scheduler.advance(by: 4)
    #expect(fixture.view.image === fixture.images[.idle][1])
    fixture.scheduler.advance(by: 0.16)
    #expect(fixture.view.image === fixture.images[.idle][0])
    fixture.controller.handleKeyDown(isEnter: true)
    #expect(fixture.view.image === fixture.images[.enter][0])
    fixture.scheduler.advance(by: 0.12)
    #expect(fixture.view.image === fixture.images[.enter][1])
    fixture.scheduler.advance(by: 0.12)
    #expect(fixture.view.image === fixture.images[.typing][0])
    fixture.images[.enter] = [fixture.images[.enter][0]]
    fixture.controller.handleKeyDown(isEnter: true)
    fixture.scheduler.advance(by: 0.57)
    #expect(fixture.view.image === fixture.images[.enter][0])
    fixture.scheduler.advance(by: 0.02)
    #expect(fixture.view.image === fixture.images[.typing][0])
    fixture.controller.shutdown()
}

@Test @MainActor func pauseReplacementAndShutdownRejectStaleCallbacks() {
    let fixture = AnimationFixture()
    fixture.controller.start()
    fixture.controller.handleKeyDown(isEnter: true)
    fixture.controller.setPaused(true)
    let pausedImage = fixture.view.image
    #expect(fixture.scheduler.pendingCount == 0)
    fixture.scheduler.fireCancelledActions()
    fixture.scheduler.advance(by: 400)
    #expect(fixture.view.image === pausedImage)
    fixture.controller.imageSetDidChange(resetActivity: true)
    #expect(fixture.scheduler.pendingCount == 0)
    fixture.controller.setPaused(false)
    fixture.scheduler.advance(by: 25)
    fixture.images[.sleep] = [NSImage(size: NSSize(width: 3, height: 3))]
    fixture.controller.imageSetDidChange()
    let replacement = fixture.view.image
    fixture.scheduler.fireCancelledActions()
    #expect(fixture.view.image === replacement)
    fixture.controller.shutdown()
    #expect(fixture.scheduler.pendingCount == 0)
    fixture.scheduler.fireCancelledActions()
    fixture.scheduler.advance(by: 400)
    #expect(fixture.view.image === replacement)
}

@Test @MainActor func incompleteImageReplacementCancelsEverySchedule() {
    let fixture = AnimationFixture()
    fixture.controller.start()
    fixture.controller.handleKeyDown(isEnter: true)
    fixture.images = PetImageSet()
    fixture.controller.imageSetDidChange()
    #expect(fixture.scheduler.pendingCount == 0)
    fixture.scheduler.fireCancelledActions()
    #expect(fixture.controller.currentPhase == nil)
}
