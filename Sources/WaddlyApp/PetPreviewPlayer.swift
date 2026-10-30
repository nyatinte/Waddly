import AppKit
import WaddlyCore

/// Plays the registered frames. The demo loop keeps the pet alive on screen; a category button plays
/// that animation once and then falls through into the loop.
@MainActor
final class PetPreviewPlayer {
    struct Shot {
        let image: NSImage
        let seconds: TimeInterval
    }

    private let showImage: @MainActor (NSImage?) -> Void
    /// Injectable so tests can drive the sequence without waiting on real time.
    private let sleep: @MainActor (TimeInterval) async -> Void
    private var images = PetImageSet()
    private var task: Task<Void, Never>?
    private var generation = 0
    private var activeReaction: PetImageCategory?

    init(
        showImage: @escaping @MainActor (NSImage?) -> Void,
        sleep: @escaping @MainActor (TimeInterval) async -> Void = PetPreviewPlayer.defaultSleep
    ) {
        self.showImage = showImage
        self.sleep = sleep
    }

    static func defaultSleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    var isPlaying: Bool {
        task != nil
    }

    func setImages(_ images: PetImageSet) {
        self.images = images
    }

    func playLoop() {
        start(shots: Self.demoShots(for: images), loops: true)
    }

    /// The reaction test stays idle until a real key event arrives.
    func playIdle() {
        start(shots: Self.shotSequence(for: .idle, in: images), loops: true)
    }

    func playReaction(_ category: PetImageCategory) {
        guard category != .typing || activeReaction != .typing else { return }
        start(shots: Self.shotSequence(for: category, in: images), loops: false, idleAfter: true)
        activeReaction = isPlaying ? category : nil
    }

    /// The permission step shows the pet asleep until reactions are actually live.
    func playSleeping() {
        start(shots: Self.shotSequence(for: .sleep, in: images, seconds: 2.0), loops: true)
    }

    /// Sleep → wake → typing, then settle into the normal loop.
    func playWakeUp() {
        var shots = Self.shotSequence(for: .sleep, in: images, seconds: 0.35)
        shots += Self.shotSequence(for: .idle, in: images, seconds: 0.6)
        shots += Self.shotSequence(for: .typing, in: images, seconds: 0.32)
        start(shots: shots, loops: false)
    }

    func play(_ category: PetImageCategory) {
        let lead = Self.shotSequence(for: category, in: images)
        guard !lead.isEmpty else {
            playLoop()
            return
        }
        start(shots: lead + Self.demoShots(for: images), loops: true)
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        activeReaction = nil
    }

    /// Shows each shot for its own duration before advancing. The first shot must be held, not
    /// immediately overwritten: a one-shot category such as Enter would otherwise never be seen.
    private func start(shots: [Shot], loops: Bool, idleAfter: Bool = false) {
        stop()
        guard !shots.isEmpty else {
            showImage(nil)
            return
        }
        generation += 1
        let token = generation
        task = Task { @MainActor [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let self, token == generation else { return }
                let shot = shots[index % shots.count]
                showImage(shot.image)
                index += 1
                await sleep(shot.seconds)
                guard !Task.isCancelled, token == generation else { return }
                if !loops, index >= shots.count {
                    if idleAfter {
                        playIdle()
                    } else {
                        playLoop()
                    }
                    return
                }
            }
        }
    }

    /// Idle (with blink) → typing → Enter → sleep, then back to idle.
    static func demoShots(for images: PetImageSet) -> [Shot] {
        guard images.isComplete else { return [] }
        var sequence = shotSequence(for: .idle, in: images, seconds: 1.5)
        sequence += shotSequence(for: .typing, in: images, seconds: 0.32)
        sequence += shotSequence(for: .enter, in: images, seconds: 0.9)
        sequence += shotSequence(for: .sleep, in: images, seconds: 1.2)
        return sequence
    }

    private static func shotSequence(
        for category: PetImageCategory,
        in images: PetImageSet,
        seconds: TimeInterval? = nil
    ) -> [Shot] {
        let durations: [TimeInterval] = switch category {
        case .idle: [1.5, 0.5]
        case .typing: [0.32, 0.32, 0.32, 0.32]
        case .enter: [1.1]
        case .sleep: [1.2, 1.6]
        }
        return images[category].enumerated().map { index, image in
            Shot(image: image, seconds: seconds ?? durations[min(index, durations.count - 1)])
        }
    }
}
