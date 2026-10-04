import AppKit
import QuartzCore
import WaddlyCore

@MainActor
final class PetAnimationController {
    private let petView: NSImageView
    private let petImages: () -> PetImageSet
    private let hasCompletePetImageSet: () -> Bool
    private let typingMotion: () -> TypingMotion
    private let isBreathingEnabled: () -> Bool
    private let scheduler: any AnimationScheduling
    private let blinkDelay: () -> TimeInterval

    private var phaseWork: AnimationCancellation?
    private var idleBlinkWork: AnimationCancellation?
    private var sleepAnimationWork: AnimationCancellation?
    private var enterReactionWork: AnimationCancellation?
    private var phaseWorkGeneration = 0
    private var idleBlinkGeneration = 0
    private var sleepAnimationGeneration = 0
    private var enterReactionGeneration = 0
    private var enterReactionFrameIndex = 0
    private var lastInputTime: TimeInterval
    private var lastTypingFrameTime: TimeInterval = 0
    private var typingFrameIndex = 0
    private var idleFrameIndex = 1
    private var sleepFrameIndex = 0

    private(set) var isPaused = false
    private(set) var currentPhase: PetPhase?

    init(
        petView: NSImageView,
        petImages: @escaping () -> PetImageSet,
        hasCompletePetImageSet: @escaping () -> Bool,
        typingMotion: @escaping () -> TypingMotion,
        isBreathingEnabled: @escaping () -> Bool,
        scheduler: any AnimationScheduling = ContinuousAnimationScheduler(),
        blinkDelay: @escaping () -> TimeInterval = { Double.random(in: 4 ... 8) }
    ) {
        self.petView = petView
        self.petImages = petImages
        self.hasCompletePetImageSet = hasCompletePetImageSet
        self.typingMotion = typingMotion
        self.isBreathingEnabled = isBreathingEnabled
        self.scheduler = scheduler
        self.blinkDelay = blinkDelay
        lastInputTime = scheduler.now - 2.5
    }

    func start() {
        schedulePhaseChange()
    }

    func handleKeyDown(isEnter: Bool) {
        guard hasCompletePetImageSet(), !isPaused else { return }
        let startsTyping = currentPhase != .typing
        let interruptedEnterReaction = enterReactionWork != nil
        stopEnterReaction()
        stopSleepAnimation()
        lastInputTime = scheduler.now
        stopPhaseWork()
        stopIdleBlink()
        petView.layer?.removeAnimation(forKey: "idle-breathe")
        petView.layer?.removeAnimation(forKey: "sleep-breathe")
        currentPhase = .typing

        if isEnter {
            playEnterReaction()
        } else if startsTyping {
            typingFrameIndex = 0
            show(petImages()[.typing][typingFrameIndex])
            typingFrameIndex += 1
            lastTypingFrameTime = lastInputTime
            bounce()
        } else if interruptedEnterReaction || lastInputTime - lastTypingFrameTime >= 0.075 {
            let images = petImages()[.typing]
            show(images[typingFrameIndex % images.count])
            typingFrameIndex += 1
            lastTypingFrameTime = lastInputTime
            bounce()
        }
        schedulePhaseChange()
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            stopAllWork()
            petView.layer?.removeAllAnimations()
            return
        }

        lastInputTime = scheduler.now
        currentPhase = nil
        if hasCompletePetImageSet() {
            show(petImages()[.typing][0])
            schedulePhaseChange()
        }
    }

    func imageSetDidChange(resetActivity: Bool = false) {
        if resetActivity {
            lastInputTime = scheduler.now - 2.5
            currentPhase = nil
            stopPhaseWork()
        }
        stopEnterReaction()
        stopIdleBlink()
        stopSleepAnimation()

        guard !isPaused else { return }
        guard hasCompletePetImageSet() else {
            currentPhase = nil
            stopPhaseWork()
            petView.layer?.removeAllAnimations()
            return
        }

        guard let currentPhase else {
            currentPhase = .idle
            show(petImages()[.idle][0])
            breathe(key: "idle-breathe", breathScale: 1.01, duration: 3.2)
            scheduleIdleBlink()
            schedulePhaseChange()
            return
        }

        switch currentPhase {
        case .typing:
            typingFrameIndex = 1
            show(petImages()[.typing][0])
        case .idle:
            show(petImages()[.idle][0])
            scheduleIdleBlink()
        case .sleeping:
            sleepFrameIndex = 0
            show(petImages()[.sleep][0])
            scheduleSleepAnimation()
        case .frozen:
            if let lastSleepImage = petImages()[.sleep].last {
                show(lastSleepImage)
            }
        }
    }

    func breathingPreferenceDidChange() {
        petView.layer?.removeAnimation(forKey: "idle-breathe")
        petView.layer?.removeAnimation(forKey: "sleep-breathe")
        guard isBreathingEnabled(), !isPaused else { return }
        switch currentPhase {
        case .idle: breathe(key: "idle-breathe", breathScale: 1.01, duration: 3.2)
        case .sleeping: breathe()
        case .typing, .frozen, nil: break
        }
    }

    func typingMotionDidChange(_ motion: TypingMotion) {
        if motion == .off {
            petView.layer?.removeAnimation(forKey: "type-bounce")
        }
    }

    func shutdown() {
        stopAllWork()
        petView.layer?.removeAllAnimations()
    }
}

private extension PetAnimationController {
    private func schedulePhaseChange() {
        stopPhaseWork()
        guard hasCompletePetImageSet(), !isPaused else { return }
        let elapsed = scheduler.now - lastInputTime
        let phase = PetPhase.after(elapsed)
        if phase != currentPhase {
            currentPhase = phase
            updatePet(for: phase)
        }

        let nextBoundary: TimeInterval? = switch phase {
        case .typing: 2.5
        case .idle: 25
        case .sleeping: 325
        case .frozen: nil
        }
        guard let nextBoundary else { return }
        let generation = phaseWorkGeneration
        phaseWork = scheduler.schedule(
            after: max(0.05, nextBoundary - elapsed),
            repeats: false
        ) { [weak self] in
            guard let self, phaseWorkGeneration == generation else { return }
            schedulePhaseChange()
        }
    }

    private func updatePet(for phase: PetPhase) {
        guard hasCompletePetImageSet() else { return }
        switch phase {
        case .typing:
            break
        case .idle:
            petView.layer?.removeAllAnimations()
            idleFrameIndex = 1
            show(petImages()[.idle][0])
            breathe(key: "idle-breathe", breathScale: 1.01, duration: 3.2)
            scheduleIdleBlink()
        case .sleeping:
            stopIdleBlink()
            petView.layer?.removeAllAnimations()
            sleepFrameIndex = 0
            show(petImages()[.sleep][0])
            breathe()
            scheduleSleepAnimation()
        case .frozen:
            stopIdleBlink()
            stopSleepAnimation()
            petView.layer?.removeAllAnimations()
            if let lastSleepImage = petImages()[.sleep].last {
                show(lastSleepImage)
            }
        }
    }

    private func show(_ image: NSImage) {
        petView.image = image
    }

    private func bounce() {
        let motion = typingMotion()
        guard motion != .off, let layer = petView.layer else { return }
        layer.removeAnimation(forKey: "type-bounce")
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = [0, motion.amplitude, 0]
        animation.keyTimes = [0, 0.45, 1]
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "type-bounce")
    }

    private func playEnterReaction() {
        let sequence = petImages()[.enter]
        enterReactionFrameIndex = 0
        show(sequence[enterReactionFrameIndex])
        enterReactionFrameIndex += 1

        if let layer = petView.layer {
            layer.removeAnimation(forKey: "type-bounce")
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1, 0.86, 1.12, 0.96, 1]
            scale.keyTimes = [0, 0.2, 0.48, 0.72, 1]
            scale.duration = 0.58

            let press = CAKeyframeAnimation(keyPath: "transform.translation.y")
            press.values = [0, 8, -5, 2, 0]
            press.keyTimes = scale.keyTimes
            press.duration = scale.duration

            let impact = CAAnimationGroup()
            impact.animations = [scale, press]
            impact.duration = scale.duration
            impact.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(impact, forKey: "enter-impact")
        }

        let generation = enterReactionGeneration
        enterReactionWork = scheduler.schedule(
            after: sequence.count > 1 ? 0.12 : 0.58,
            repeats: sequence.count > 1
        ) { [weak self] in
            guard let self, enterReactionGeneration == generation else { return }
            guard currentPhase == .typing, !isPaused,
                  hasCompletePetImageSet()
            else {
                stopEnterReaction()
                return
            }
            guard enterReactionFrameIndex < sequence.count else {
                finishEnterReaction()
                show(petImages()[.typing][0])
                return
            }
            show(sequence[enterReactionFrameIndex])
            enterReactionFrameIndex += 1
        }
    }

    private func finishEnterReaction() {
        enterReactionWork?.invalidate()
        enterReactionWork = nil
        enterReactionGeneration += 1
    }

    private func stopEnterReaction() {
        enterReactionWork?.invalidate()
        enterReactionWork = nil
        enterReactionGeneration += 1
        petView.layer?.removeAnimation(forKey: "enter-impact")
    }

    private func breathe(
        key: String = "sleep-breathe",
        breathScale: CGFloat = 1.018,
        duration: CFTimeInterval = 1.5
    ) {
        guard isBreathingEnabled(), !isPaused, hasCompletePetImageSet(),
              let layer = petView.layer else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1.0
        animation.toValue = breathScale
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key)
    }
}

private extension PetAnimationController {
    private func scheduleIdleBlink() {
        stopIdleBlink()
        guard currentPhase == .idle, !isPaused, petImages()[.idle].count > 1 else { return }
        let generation = idleBlinkGeneration
        idleBlinkWork = scheduler.schedule(
            after: blinkDelay(),
            repeats: false
        ) { [weak self] in
            guard let self, idleBlinkGeneration == generation,
                  currentPhase == .idle, !self.isPaused else { return }
            let blinkImages = petImages()[.idle]
            guard blinkImages.count > 1 else { return }
            idleFrameIndex = Int.random(in: 1 ..< blinkImages.count)
            show(blinkImages[idleFrameIndex])
            idleBlinkWork = scheduler.schedule(after: 0.16, repeats: false) { [weak self] in
                guard let self, idleBlinkGeneration == generation,
                      currentPhase == .idle, !self.isPaused else { return }
                idleBlinkWork = nil
                show(petImages()[.idle][0])
                scheduleIdleBlink()
            }
        }
    }

    private func scheduleSleepAnimation() {
        stopSleepAnimation()
        guard currentPhase == .sleeping, !isPaused, petImages()[.sleep].count > 1 else { return }
        let generation = sleepAnimationGeneration
        sleepAnimationWork = scheduler.schedule(after: 1.5, repeats: true) { [weak self] in
            guard let self, sleepAnimationGeneration == generation,
                  currentPhase == .sleeping, !self.isPaused else { return }
            let sleepImages = petImages()[.sleep]
            guard !sleepImages.isEmpty else { return }
            sleepFrameIndex = (sleepFrameIndex + 1) % sleepImages.count
            show(sleepImages[sleepFrameIndex])
        }
    }

    private func stopPhaseWork() {
        phaseWorkGeneration += 1
        phaseWork?.invalidate()
        phaseWork = nil
    }

    private func stopIdleBlink() {
        idleBlinkGeneration += 1
        idleBlinkWork?.invalidate()
        idleBlinkWork = nil
    }

    private func stopSleepAnimation() {
        sleepAnimationGeneration += 1
        sleepAnimationWork?.invalidate()
        sleepAnimationWork = nil
    }

    private func stopAllWork() {
        stopPhaseWork()
        stopIdleBlink()
        stopSleepAnimation()
        stopEnterReaction()
    }
}
