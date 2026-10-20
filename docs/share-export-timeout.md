# v1.4.0 share-movie timeout investigation (#143)

## Evidence and current disposition

Release source: `ba38a08f80c7c4f940e36508c8eb69d4a2cabf40`.

| Execution | Result |
| --- | --- |
| [Release run 39393172673](https://github.com/nyatinte/Waddly/actions/runs/39393172673) | Full selection completed: 236 tests / 24 suites; one failing test, plus one known issue. `shareMovieExportsFiveSecondsOfThePetAnimation` threw `.timedOut` after 120.077 seconds. Packaging and publication were skipped. |
| [Main CI run 39393166567](https://github.com/nyatinte/Waddly/actions/runs/39393166567/job/118529334648), **the exact same commit** | `mise run check` completed all 236 tests / 24 suites with one known issue, then built Release. The movie test passed in 0.249 seconds. This was an independent push-triggered run, not a retry of the failed release. |
| Local unchanged-source full `mise run test` | Movie test passed in 0.058 seconds; Core completed 63 tests / 4 suites with one known issue. App tests exited early in `closingTheWizardConfirmsDiscardOfADirtySharedDraft`: **full run failed (#131)**. |

Both hosted executions used `macos-26-arm64`, image `20261013.0424.1`, macOS 26.6.2 (`25G83`). The successful CI reports Swift 6.3.3 and target `arm64-apple-macosx26.0`. The old release workflow did not print `swift --version` explicitly; its compiler diagnostics reference the same Xcode 26.6 / macOS 26.5 SDK paths. Future release executions print the OS, architecture and Swift version explicitly rather than inferring toolchain equality from the image name.

The failed release also passed both preceding real-writer finalization tests (0.310 / 0.317 seconds), and subsequently exported the reduced-frame/mixed-dimension movie in 0.212 seconds. Therefore this is **not evidence that all encoding on that runner was broken**, nor evidence for a simple first-encoder/cold-start explanation.

**#143 remains open.** A complete successful full test run on the exact release source is established without retries or selection reduction. The remaining criterion—identifying the cause/classifying it as a runner/AVFoundation transient versus a reproducible writer defect—is not established. A run-specific stall is consistent with these observations, but is not a proven root cause. The old failure log has no readiness/frame/finalization progress, so it cannot distinguish those phases retroactively. #131's local early termination is a separate failure, not an explanation for this completed release run.

## Bounded diagnostic change

`Tests/WaddlyCoreTests/PetShareExportTestSupport.swift` observes the existing `MovieWriterHooks` seams and, only when the export throws, prints:

- readiness callback count;
- successfully appended frame count;
- whether finalization was requested and its completion was delivered;
- error domain/code and OS version.

It does not print imported images, file URLs, NSError user-info or localized error descriptions. It rethrows the original error. All original hooks are forwarded, including the return value from the per-frame hook, so injected stalls, deadlines, cancellation and cleanup assertions remain in effect. The snapshot is taken when the error is returned (after the bounded cancellation grace wait), **not necessarily at the instant the deadline expired**.

The canonical movie test uses the same internal writer implementation, standard hooks and 120-second timeout with this observer. Duration and 384×384 track-size assertions remain unchanged. The mixed-dimension movie test continues to exercise the public `writeMovie` entry point directly.

Existing deterministic tests also use the observer to exercise three distinguishable progress signatures:

| Injected condition | Observed signature |
| --- | --- |
| Readiness callback withheld past deadline | `readinessCallbacks=0; appendedFrames=0; finalizationRequested=false; finalizationCompleted=false` |
| Deadline after the first appended frame | `readinessCallbacks=1; appendedFrames=1; finalizationRequested=false; finalizationCompleted=false` |
| Cancellation while finalizer withholds completion | `appendedFrames=60; finalizationRequested=true; finalizationCompleted=false` (callback count is scheduler-dependent) |

These are **intentional expected-error controls**, not reproductions of the original release failure. Their diagnostic lines do not mean those tests failed. They retain their original cleanup and cancellation assertions.

No production writer logic, codec, queue policy, deadline, retry policy or release gate changes. The safety allowlist only relocates the seven existing temporary-file cleanup exceptions after moving the test helper; no new exception is introduced. Local `mise run check` passed format/lint/complexity/safety and the Core run (63 tests / 4 suites with one known issue), then failed closed on #131. The observed movie test passed in 0.057 seconds. After the final error-formatting change, full `mise run test` again completed Core (63 tests / 4 suites, movie test 0.058 seconds), emitted all three expected progress signatures above, and failed on the same #131 early exit. This run verifies the changed diagnostic, not a retry offered as a green full-run result. A separate `mise run build` completed and signed the Release app. Neither result is represented as a local full-suite pass.

## Remaining investigation / release gate

1. Keep the original failed run and exact-source successful run as independent evidence; do not keep retrying the failed release until it turns green.
2. If a full run on the instrumented source fails, use its phase signature to bound the next experiment. Counters alone cannot identify a native encoder failure, a hardware-service problem, or prove a deadlock; obtain native writer/service diagnostics before choosing a product fix.
3. For a suspected writer defect, require a controlled reproduction and a regression assertion before altering scheduling or cancellation. For a suspected hosted-runner transient, require runner/native-service evidence rather than inferring it from one later success.
4. Explicitly decide release disposition after reviewing that evidence. This diagnostic change is **not** a root-cause fix or an authorization to publish.

No release rerun, tag movement, release asset publication, or Homebrew update was performed. The existing v1.4.0 tag still references the original source, so it does not acquire these diagnostics retroactively.
