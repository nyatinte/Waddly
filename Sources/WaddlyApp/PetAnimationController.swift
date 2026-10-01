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
    private let now: () -> TimeInterval

    private var phaseTimer: Timer?
    private var idleBlinkTimer: Timer?
    private var sleepAnimationTimer: Timer?
    private var enterReactionTimer: Timer?
    private var phaseTimerGeneration = 0
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
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.petView = petView
        self.petImages = petImages
        self.hasCompletePetImageSet = hasCompletePetImageSet
        self.typingMotion = typingMotion
        self.isBreathingEnabled = isBreathingEnabled
        self.now = now
        lastInputTime = now() - 2.5
    }

    func start() {
        schedulePhaseChange()
    }

    func handleKeyDown(isEnter: Bool) {
        guard hasCompletePetImageSet(), !isPaused else { return }
        let startsTyping = currentPhase != .typing
        let interruptedEnterReaction = enterReactionTimer != nil
        stopEnterReaction()
        stopSleepAnimation()
        lastInputTime = now()
        stopPhaseTimer()
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
            stopAllTimers()
            petView.layer?.removeAllAnimations()
            return
        }

        lastInputTime = now()
        currentPhase = nil
        if hasCompletePetImageSet() {
            show(petImages()[.typing][0])
            schedulePhaseChange()
        }
    }

    func imageSetDidChange(resetActivity: Bool = false) {
        if resetActivity {
            lastInputTime = now() - 2.5
            currentPhase = nil
            stopPhaseTimer()
        }
        stopEnterReaction()
        stopIdleBlink()
        stopSleepAnimation()

        guard hasCompletePetImageSet() else {
            currentPhase = nil
            stopPhaseTimer()
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
        stopAllTimers()
        petView.layer?.removeAllAnimations()
    }
}

private extension PetAnimationController {
    private func schedulePhaseChange() {
        stopPhaseTimer()
        guard hasCompletePetImageSet(), !isPaused else { return }
        let elapsed = now() - lastInputTime
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
        let generation = phaseTimerGeneration
        phaseTimer = Timer.scheduledTimer(
            withTimeInterval: max(0.05, nextBoundary - elapsed),
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phaseTimerGeneration == generation else { return }
                self.schedulePhaseChange()
            }
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
        enterReactionTimer = Timer.scheduledTimer(
            withTimeInterval: sequence.count > 1 ? 0.12 : 0.58,
            repeats: sequence.count > 1
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.enterReactionGeneration == generation else { return }
                guard self.currentPhase == .typing, !self.isPaused,
                      self.hasCompletePetImageSet()
                else {
                    self.stopEnterReaction()
                    return
                }
                guard self.enterReactionFrameIndex < sequence.count else {
                    self.finishEnterReaction()
                    self.show(self.petImages()[.typing][0])
                    return
                }
                self.show(sequence[self.enterReactionFrameIndex])
                self.enterReactionFrameIndex += 1
            }
        }
    }

    private func finishEnterReaction() {
        enterReactionTimer?.invalidate()
        enterReactionTimer = nil
        enterReactionGeneration += 1
    }

    private func stopEnterReaction() {
        enterReactionTimer?.invalidate()
        enterReactionTimer = nil
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
        idleBlinkTimer = Timer.scheduledTimer(
            withTimeInterval: Double.random(in: 4 ... 8),
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.idleBlinkGeneration == generation,
                      self.currentPhase == .idle, !self.isPaused else { return }
                let blinkImages = self.petImages()[.idle]
                guard blinkImages.count > 1 else { return }
                self.idleFrameIndex = Int.random(in: 1 ..< blinkImages.count)
                self.show(blinkImages[self.idleFrameIndex])
                self.idleBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.idleBlinkGeneration == generation,
                              self.currentPhase == .idle, !self.isPaused else { return }
                        self.idleBlinkTimer = nil
                        self.show(self.petImages()[.idle][0])
                        self.scheduleIdleBlink()
                    }
                }
            }
        }
    }

    private func scheduleSleepAnimation() {
        stopSleepAnimation()
        guard currentPhase == .sleeping, !isPaused, petImages()[.sleep].count > 1 else { return }
        let generation = sleepAnimationGeneration
        sleepAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.sleepAnimationGeneration == generation,
                      self.currentPhase == .sleeping, !self.isPaused else { return }
                let sleepImages = self.petImages()[.sleep]
                guard !sleepImages.isEmpty else { return }
                self.sleepFrameIndex = (self.sleepFrameIndex + 1) % sleepImages.count
                self.show(sleepImages[self.sleepFrameIndex])
            }
        }
    }

    private func stopPhaseTimer() {
        phaseTimerGeneration += 1
        phaseTimer?.invalidate()
        phaseTimer = nil
    }

    private func stopIdleBlink() {
        idleBlinkGeneration += 1
        idleBlinkTimer?.invalidate()
        idleBlinkTimer = nil
    }

    private func stopSleepAnimation() {
        sleepAnimationGeneration += 1
        sleepAnimationTimer?.invalidate()
        sleepAnimationTimer = nil
    }

    private func stopAllTimers() {
        stopPhaseTimer()
        stopIdleBlink()
        stopSleepAnimation()
        stopEnterReaction()
    }
}
