# Swift safety checks

The required `mise run check` validation runs SwiftLint in strict mode, Swift 6 compiler checks, and the SwiftSyntax-based `swift-safety-check`. SwiftLint owns forced casts, forced try, and forced unwrap rules; the safety checker is limited to project policies SwiftLint and the compiler do not express directly: unsafe casts, raw pointer/Unmanaged use, unchecked concurrency annotations, actor assumptions, unbounded zero-argument `wait()`, unapproved switch defaults, empty catch clauses, `try?` that discards a file write or delete error, and compiler flags that disable a safety guarantee. Fixtures prove both sets of rules reject deliberately unsafe samples. The checker fails if SwiftSyntax cannot parse a scanned file or if an allowlist entry no longer matches a detected violation. `mise run safety` scans `Sources`, `Tests`, and the three `Package.swift` manifests.

## Narrow baseline exceptions

`Tools/SwiftSafetyCheck/Allowlist.json` contains only existing source locations that were reviewed while introducing the check. Each entry is tied to a rule and exact line; moving the code requires reviewing and updating the entry. New uses fail CI. Keep any new exception narrow, explain the invariant in the change, and require review.

The movie export no longer needs an exception: `appendMovieFrames` bounds its wait for the writer, and `makeVideoPixelBuffer` unlocks the buffer on every path after a successful lock. `PetShareMovieWriter` keeps two narrow concurrency exceptions instead. `MovieWriterState` is `@unchecked Sendable` because AVFoundation's writer classes are non-Sendable: the class creates them once, mutates them only on the serial export queue, and keeps every mutable counter behind an `OSAllocatedUnfairLock`, so the waiting caller's terminal reads are synchronized with the queue's exactly-once terminal transition. Its `@preconcurrency import AVFoundation` documents that same boundary; the public `PetShareExporter` file imports AVFoundation normally. `AppSettings` is the other `@unchecked Sendable` type: `UserDefaults` is documented as thread-safe and is its only stored state, so the conformance only stands in for `UserDefaults` not being marked `Sendable`. The image test helper also has two exact pointer-use exceptions: it allocates a buffer and releases it with `defer`, and passes that buffer to Core Graphics.

`KeyboardMonitor` has four exact `Unmanaged` exceptions for its Core Graphics event-tap bridge. `AppDelegate` retains the monitor, `stop()` removes the run-loop source and invalidates the tap before clearing it, and the callback uses unretained conversions to avoid creating an ownership cycle while returning the event with the callback API's expected ownership.

## Empty catch clauses

An empty `catch` body discards the error with no log and no state change, so the rule refuses one by default. `AnimationScheduler` has the only `empty-catch` exception: `catch is CancellationError {}` intentionally swallows cancellation because cancelling the scheduled animation is the normal shutdown path and carries no failure; every other error reaches the following `catch` and `assertionFailure`.

## Silenced file mutations and retry limits

`try?` on a file mutation has no retry path. It discards the thrown error, so the caller cannot tell "already absent" from "permission denied" or "disk full", and nothing is logged. The allowlisted production sites are cleanup or best-effort write-back:

- The share-window sites delete staged `WaddlyShare-*` files under the system temporary directory: only the sprite after a failed export, or both files after a successful export is discarded. A pending movie stays owned by the export queue even after its bounded cancellation acknowledgement expires. A failed delete leaves a temporary file for the OS to reclaim, and the surrounding operation already throws or returns its in-memory result. If cancellation races with a movie that already completed, the exporter deliberately preserves that completed output; the failed share attempt can leave it in the temporary directory for the OS to reclaim rather than risk deleting a still-owned output.
- `PetImageStorage.removeObsoleteFiles` deletes obsolete PNG frames from the production Application Support directory (`applicationSupport/Waddly/PetImages`, or `Waddly-<suffix>` for a development build), not a temporary directory the OS reclaims. It returns `Void`, and the caller runs it fire-and-forget after committing the new manifest, so a failed removal is genuinely best-effort: it leaves an unreferenced PNG in Application Support with no error, no retry, and no signal, and the next run does not revisit it because removal is driven only by the previous manifest's names. Keeping it off the critical path is a deliberate trade-off; a durable cleanup would have to report the failure instead.
- `PetImageCore.load` rewrites an oversized PNG with `try? optimized.pngData.write(to:options:.atomic)`. An atomic write stages and renames, so a failed write leaves the previous file intact, and the downsampled image is still returned in memory; the next load retries the write. A silent partial file is not possible through the atomic path.
- `PetShareExporter.writeMovie` removes any stale output with `try?` before creating the asset writer. If that removal fails, `AVAssetWriter(outputURL:)` throws on the existing file and the error propagates, so `try?` does not mask it.
- `PetShareExporter.appendMovieFrames` removes the output of a writer that ended on a terminal, non-completed status after finalization, once the wait has returned (`PetShareExporter.swift`). The finalizer's completion already claimed the export's terminal transition, so `cancelOnQueue` cannot run afterwards; the writer is quiescent, so removal is safe. An active writer after the bounded cancellation acknowledgement expires, and a completed writer in the cancellation race, are still never deleted.
- Tests remove their temporary directories and movies in `defer`. A failed removal leaks a temporary file for the OS to reclaim and cannot change assertions.

None of these sites retries a failed mutation. A new `silenced-file-mutation` hit is a review prompt: if the write must be durable, use `try`, surface the error, and define the retry or recovery explicitly.

## Compiler flag audit

No target sets `unsafeFlags`, and no build script passes `-Ounchecked`, `-enforce-exclusivity=unchecked`, `-strict-concurrency=minimal`, or `-suppress-warnings`. The three manifests (`Package.swift` and `Tools/SwiftSafetyCheck/Package.swift` at `swift-tools-version: 6.0`, `Performance/Package.swift` at `6.2`) use only default SwiftPM settings, strict concurrency remains on, and none declares `swiftSettings`. The `unsafe-compiler-flags` rule flags `.unsafeFlags(...)` calls and those flag strings in any scanned file, so adding the manifests to the scan path makes the audit enforced rather than documented only. The rule is a review gate for the listed fragments; it does not enumerate every compiler invocation.

## What static checks cannot prove

Syntax checks cannot prove that every Core Foundation or C API resource is released on every path, that a lock is balanced across all exits, or that a writer always completes. Those guarantees need targeted tests and runtime leak tools. Swift 6 strict concurrency and the compiler's enum exhaustiveness diagnostics remain part of the normal build; the explicit default-case check prevents a new catch-all from hiding future cases.

The checker intentionally does not ban every `Any` or `AnyObject`, nor every protocol or `Protocol` existential: Apple APIs, Objective-C bridges, and normal Swift abstraction use these legitimately. It checks syntax, not resolved symbols, value flow, or ownership semantics; it is a review gate, not a proof of safety. Review type-erasure additions in context and prefer concrete types or a named protocol when possible. In particular, the new rules do not trace a value: `silenced-file-mutation` unwraps `await`, redundant parentheses (around the expression or the callee), and single-element tuple wrappers before matching the called member name, so it neither proves that a matched `write` touches the file system nor detects an indirect mutation through a helper. The `empty-catch` rule reports a catch whose body has no statements; a body that logs and continues passes even if the error is effectively dropped.

## CodeQL availability evaluation

CodeQL was evaluated, not adopted. On 2026-10-17 (local checks on the pinned toolchain):

- `command -v codeql` reported nothing; the CodeQL CLI is not installed.
- `gh extension list` listed only `gh-attach` and `gh-stack`; the `gh codeql` extension is not installed.
- No `.github/workflows` file configures CodeQL, SARIF, or code scanning.
- `gh api repos/nyatinte/Waddly/code-scanning/default-setup` returned `{"languages":["actions","swift"],"query_suite":"default","state":"not-configured"}`, so GitHub-hosted code scanning supports Swift for this repository but is not enabled.

Enabling CodeQL would add a new workflow (or a repository default-setup change) and a Swift analysis job, and would have to be reviewed and verified as its own change. It is not part of this slice, and nothing here claims the syntax checker provides dataflow or taint analysis. If CodeQL is enabled later, treat its alerts as an additional signal alongside these checks rather than replacing them.
