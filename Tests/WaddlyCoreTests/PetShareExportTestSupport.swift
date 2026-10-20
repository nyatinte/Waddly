import AVFoundation
import Foundation
import os
@testable import WaddlyCore

/// Observe the real writer without changing deadlines, scheduling, failure hooks or error types.
/// Report only counters and OS version on failure, never imported pixels or file paths.
func exportMovieWithDiagnostics(
    from images: PetImageSet,
    to url: URL,
    timeout: DispatchTimeInterval,
    cancellation: PetShareExportCancellation = PetShareExportCancellation(),
    hooks: MovieWriterHooks = MovieWriterHooks()
) throws {
    let progress = OSAllocatedUnfairLock(initialState: (
        callbacks: 0, frames: 0, finalizing: false, completed: false
    ))
    var observed = hooks
    observed.scheduleMediaData = { input, queue, encode in
        hooks.scheduleMediaData(input, queue) {
            progress.withLock { $0.callbacks += 1 }
            encode()
        }
    }
    observed.afterFrameAppended = { count in
        progress.withLock { $0.frames = count }
        return hooks.afterFrameAppended(count)
    }
    observed.finalizeWriter = { writer, completion in
        progress.withLock { $0.finalizing = true }
        hooks.finalizeWriter(writer) {
            progress.withLock { $0.completed = true }
            completion()
        }
    }
    do {
        try PetShareExporter.writeMovie(
            from: images,
            to: url,
            timeout: timeout,
            cancellation: cancellation,
            hooks: observed
        )
    } catch {
        let snapshot = progress.withLock { $0 }
        let failure = error as NSError
        print("Movie export failed: \(failure.domain) (\(failure.code)); readinessCallbacks=\(snapshot.callbacks); "
            + "appendedFrames=\(snapshot.frames); finalizationRequested=\(snapshot.finalizing); "
            + "finalizationCompleted=\(snapshot.completed); "
            + "os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        throw error
    }
}
