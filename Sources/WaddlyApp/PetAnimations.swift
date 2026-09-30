import AppKit
import QuartzCore
import WaddlyCore

extension AppDelegate {
    func receivedKeyDown(isEnter: Bool) {
        guard hasCompletePetImageSet, !isPaused else { return }
        let startsTyping = currentPhase != .typing
        let interruptedEnterReaction = enterReactionTimer != nil
        stopEnterReaction()
        sleepAnimationTimer?.invalidate()
        sleepAnimationTimer = nil
        lastInputTime = ProcessInfo.processInfo.systemUptime
        phaseTimer?.invalidate()
        idleBlinkTimer?.invalidate()
        idleBlinkTimer = nil
        petView.layer?.removeAnimation(forKey: "idle-breathe")
        petView.layer?.removeAnimation(forKey: "sleep-breathe")
        currentPhase = .typing

        if isEnter {
            playEnterReaction()
        } else if startsTyping {
            typingFrameIndex = 0
            show(petImages[.typing][typingFrameIndex])
            typingFrameIndex += 1
            lastTypingFrameTime = lastInputTime
            bounce()
        } else if interruptedEnterReaction || lastInputTime - lastTypingFrameTime >= 0.075 {
            show(petImages[.typing][typingFrameIndex % petImages[.typing].count])
            typingFrameIndex += 1
            lastTypingFrameTime = lastInputTime
            bounce()
        }
        schedulePhaseChange()
    }

    func schedulePhaseChange() {
        phaseTimer?.invalidate()
        guard hasCompletePetImageSet else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - lastInputTime
        let phase = PetPhase.after(elapsed)
        if phase != currentPhase {
            currentPhase = phase
            updatePet(for: phase)
        }

        let nextBoundary: TimeInterval?
        switch phase {
        case .typing: nextBoundary = 2.5
        case .idle: nextBoundary = 25
        case .sleeping: nextBoundary = 325
        case .frozen: nextBoundary = nil
        }
        guard let nextBoundary else { return }
        phaseTimer = Timer.scheduledTimer(
            withTimeInterval: max(0.05, nextBoundary - elapsed),
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePhaseChange() }
        }
    }

    private func updatePet(for phase: PetPhase) {
        guard hasCompletePetImageSet else { return }
        switch phase {
        case .typing:
            break
        case .idle:
            petView.layer?.removeAllAnimations()
            idleFrameIndex = 1
            show(petImages[.idle][0])
            breathe(key: "idle-breathe", breathScale: 1.01, duration: 3.2)
            scheduleIdleBlink()
        case .sleeping:
            idleBlinkTimer?.invalidate()
            idleBlinkTimer = nil
            petView.layer?.removeAllAnimations()
            sleepFrameIndex = 0
            show(petImages[.sleep][0])
            breathe()
            scheduleSleepAnimation()
        case .frozen:
            idleBlinkTimer?.invalidate()
            idleBlinkTimer = nil
            sleepAnimationTimer?.invalidate()
            sleepAnimationTimer = nil
            petView.layer?.removeAllAnimations()
            if let lastSleepImage = petImages[.sleep].last {
                show(lastSleepImage)
            }
        }
    }

    func show(_ image: NSImage) {
        petView.image = image
    }

    private func bounce() {
        let motion = typingMotion
        guard motion != .off else { return }
        guard let layer = petView.layer else { return }
        layer.removeAnimation(forKey: "type-bounce")
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = [0, motion.amplitude, 0]
        animation.keyTimes = [0, 0.45, 1]
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "type-bounce")
    }

    private func playEnterReaction() {
        let sequence = petImages[.enter]
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

        enterReactionTimer = Timer.scheduledTimer(
            withTimeInterval: sequence.count > 1 ? 0.12 : 0.58,
            repeats: sequence.count > 1
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.currentPhase == .typing, !self.isPaused else {
                    self.enterReactionTimer?.invalidate()
                    self.enterReactionTimer = nil
                    return
                }
                guard self.enterReactionFrameIndex < sequence.count else {
                    self.enterReactionTimer?.invalidate()
                    self.enterReactionTimer = nil
                    self.show(self.petImages[.typing][0])
                    return
                }
                self.show(sequence[self.enterReactionFrameIndex])
                self.enterReactionFrameIndex += 1
            }
        }
    }

    func stopEnterReaction() {
        enterReactionTimer?.invalidate()
        enterReactionTimer = nil
        petView.layer?.removeAnimation(forKey: "enter-impact")
    }

    func breathe(key: String = "sleep-breathe", breathScale: CGFloat = 1.018, duration: CFTimeInterval = 1.5) {
        guard isBreathingEnabled, !isPaused, hasCompletePetImageSet,
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

    func scheduleIdleBlink() {
        idleBlinkTimer?.invalidate()
        guard currentPhase == .idle, !isPaused, petImages[.idle].count > 1 else { return }
        idleBlinkTimer = Timer.scheduledTimer(
            withTimeInterval: Double.random(in: 4...8),
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.currentPhase == .idle, !self.isPaused else { return }
                let blinkImages = self.petImages[.idle]
                self.idleFrameIndex = Int.random(in: 1..<blinkImages.count)
                self.show(blinkImages[self.idleFrameIndex])
                self.idleBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.currentPhase == .idle, !self.isPaused else { return }
                        self.show(self.petImages[.idle][0])
                        self.scheduleIdleBlink()
                    }
                }
            }
        }
    }

    func scheduleSleepAnimation() {
        sleepAnimationTimer?.invalidate()
        guard currentPhase == .sleeping, !isPaused, petImages[.sleep].count > 1 else { return }
        sleepAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.currentPhase == .sleeping, !self.isPaused else { return }
                let sleepImages = self.petImages[.sleep]
                self.sleepFrameIndex = (self.sleepFrameIndex + 1) % sleepImages.count
                self.show(sleepImages[self.sleepFrameIndex])
            }
        }
    }

}
