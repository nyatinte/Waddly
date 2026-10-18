// AVFoundation marks its asset writer classes NS_SWIFT_NONSENDABLE. An export creates them on the
// caller's thread and touches them only on the serial export queue, so `@preconcurrency` suppresses no
// diagnostic that `MovieWriterState`'s documented confinement does not already cover.
@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import os

/// A frame of the exported movie with the time it occupies.
struct ScheduledShot {
    let image: CGImage
    let duration: TimeInterval
}

private let movieFrameRate: Int32 = 12
private let movieFrameCount = 60
/// How long a waiting export sleeps before it rechecks its cancellation token.
private let cancellationPollInterval = DispatchTimeInterval.milliseconds(20)
/// Bounds the wait for the export queue to stop the writer before the caller cleans up the output.
private let cancellationGracePeriod = DispatchTimeInterval.seconds(5)

/// Schedules the media-data callback that owns the writer. Tests inject a delayed queue to model a stalled encoder.
typealias MediaDataScheduler = @Sendable (AVAssetWriterInput, DispatchQueue, @escaping @Sendable () -> Void) -> Void

/// The writer's asynchronous steps. Tests replace them to stall the encoder deterministically.
struct MovieWriterHooks: Sendable {
    /// Requests the next batch of frames. Tests inject a stalled or instrumented queue.
    var scheduleMediaData: MediaDataScheduler = { input, queue, block in
        input.requestMediaDataWhenReady(on: queue, using: block)
    }

    /// Completes the writer. Tests inject a finalizer that never finishes, or one that withholds the
    /// completion so the caller cannot observe an export that actually succeeded.
    var finalizeWriter: @Sendable (AVAssetWriter, @escaping @Sendable () -> Void) -> Void = { writer, completion in
        writer.finishWriting(completionHandler: completion)
    }

    /// Runs on the serial export queue after each appended frame, with the number of frames written so
    /// far. Returning `false` stops the loop before the writer can complete. Tests block here to hold an
    /// export deadline inside a real, partial encode; production always continues.
    var afterFrameAppended: @Sendable (Int) -> Bool = { _ in true }

    /// Runs on the waiting caller's thread once the deadline or cancellation ends the wait, just before
    /// the export queue is asked to stop the writer. Tests use it to release a blocked `afterFrameAppended`.
    var willStopWriter: @Sendable () -> Void = {}
}

/// Owns one export's writer and the progress the waiting caller reads.
///
/// `@unchecked Sendable` is sound because the writer, input, and adaptor are created once and only
/// mutated on the serial export queue in `MovieWriterContext`; the waiting caller reads them only after
/// that queue signals completion. Every mutable counter lives behind `progress`, whose lock synchronizes
/// the caller's terminal reads with the queue's exactly-once terminal transition. Nothing else shares
/// this instance.
final class MovieWriterState: @unchecked Sendable {
    struct Progress: Sendable {
        var frameIndex = 0
        var error: Error?
        var didStopEncoding = false
        var didFinishEncoding = false
        var didEnd = false
    }

    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let shots: [ScheduledShot]
    private let progress = OSAllocatedUnfairLock(initialState: Progress())

    init(
        writer: AVAssetWriter,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        shots: [ScheduledShot]
    ) {
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.shots = shots
    }

    var frameIndex: Int {
        progress.withLock { $0.frameIndex }
    }

    /// True once no further frame may be appended: the loop stopped early or wrote every frame.
    var isTerminal: Bool {
        progress.withLock { $0.didStopEncoding || $0.didFinishEncoding || $0.didEnd }
    }

    var recordedError: Error? {
        progress.withLock { $0.error }
    }

    func advanceFrame() {
        progress.withLock { $0.frameIndex += 1 }
    }

    func record(error: any Error) {
        progress.withLock { $0.error = error }
    }

    /// Stops the encoding loop exactly once. Returns `true` the first time it is called.
    func stopEncoding() -> Bool {
        progress.withLock { progress in
            guard !progress.didStopEncoding else { return false }
            progress.didStopEncoding = true
            return true
        }
    }

    func finishEncoding() {
        progress.withLock { $0.didFinishEncoding = true }
    }

    /// Claims the export's single terminal transition. The winner is the one that signals `finished`.
    func endExport() -> Bool {
        progress.withLock { progress in
            guard !progress.didEnd else { return false }
            progress.didEnd = true
            return true
        }
    }
}

/// Drives one export from the serial queue that owns its writer.
///
/// The caller waits on `finished` while `encodeFrames` fills the writer; `cancelOnQueue` stops the writer
/// on the same queue, so cancellation and completion can never mutate the writer during an append.
struct MovieWriterContext: Sendable {
    let state: MovieWriterState
    let queue: DispatchQueue
    let finished: DispatchSemaphore
    let hooks: MovieWriterHooks
    let cancelOnQueue: @Sendable () -> Void

    /// Fills the writer until it has every frame, backpressure stops it, or the export is cancelled.
    func encodeFrames(cancellation: PetShareExportCancellation) {
        guard !state.isTerminal else { return }
        guard !cancellation.isCancelled else {
            // Stop the encoder requesting frames; the waiting caller still owns the cancellation result.
            if state.stopEncoding() {
                state.input.markAsFinished()
            }
            return
        }
        while state.input.isReadyForMoreMediaData, !cancellation.isCancelled {
            let frameIndex = state.frameIndex
            guard frameIndex < movieFrameCount else { break }
            let appended = autoreleasepool {
                let frame = frameForExport(state, at: frameIndex)
                guard let buffer = PetShareExporter.makeVideoPixelBuffer(frame: frame, adaptor: state.adaptor)
                else { return false }
                return state.adaptor.append(
                    buffer,
                    withPresentationTime: CMTime(value: Int64(frameIndex), timescale: movieFrameRate)
                )
            }
            guard appended else {
                state.record(error: state.writer.error ?? PetShareExportError.frameEncodingFailed)
                state.input.markAsFinished()
                cancelOnQueue()
                return
            }
            state.advanceFrame()
            guard hooks.afterFrameAppended(state.frameIndex) else {
                state.input.markAsFinished()
                return
            }
        }
        guard state.frameIndex == movieFrameCount else { return }
        state.finishEncoding()
        state.input.markAsFinished()
        hooks.finalizeWriter(state.writer) {
            guard state.endExport() else { return }
            finished.signal()
        }
    }

    /// Waits for the writer to finish, stopping it when the caller cancels or the timeout expires.
    func waitForWriter(cancellation: PetShareExportCancellation, timeout: DispatchTimeInterval) throws {
        let deadline = DispatchTime.now() + timeout
        while finished.wait(timeout: .now() + cancellationPollInterval) == .timedOut {
            guard cancellation.isCancelled || DispatchTime.now() >= deadline else { continue }
            hooks.willStopWriter()
            queue.async(execute: cancelOnQueue)
            // Wait for the queue to stop the writer before the caller removes any partial output.
            _ = finished.wait(timeout: .now() + cancellationGracePeriod)
            throw cancellation.isCancelled ? PetShareExportError.cancelled : PetShareExportError.timedOut
        }
    }
}

private func frameForExport(_ state: MovieWriterState, at frameIndex: Int) -> CGImage {
    let timeline = state.shots.reduce(0) { $0 + $1.duration }
    let elapsed = Double(frameIndex) * timeline / Double(movieFrameCount)
    var cursor = 0.0
    return state.shots.first { shot in
        defer { cursor += shot.duration }
        return elapsed < cursor + shot.duration
    }?.image ?? state.shots[0].image
}
