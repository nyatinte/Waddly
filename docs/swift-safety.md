# Swift safety checks

The required `mise run check` validation runs SwiftLint in strict mode, Swift 6 compiler checks, and the SwiftSyntax-based `swift-safety-check`. SwiftLint owns forced casts, forced try, and forced unwrap rules; the safety checker is limited to project policies SwiftLint and the compiler do not express directly: unsafe casts, raw pointer/Unmanaged use, unchecked concurrency annotations, actor assumptions, unbounded zero-argument `wait()`, and unapproved switch defaults. Fixtures prove both sets of rules reject deliberately unsafe samples. The checker fails if SwiftSyntax cannot parse a scanned file or if an allowlist entry no longer matches a detected violation.

## Narrow baseline exceptions

`Tools/SwiftSafetyCheck/Allowlist.json` contains only existing source locations that were reviewed while introducing the check. Each entry is tied to a rule and exact line; moving the code requires reviewing and updating the entry. New uses fail CI. Keep any new exception narrow, explain the invariant in the change, and require review.

The movie export no longer needs an exception: `appendMovieFrames` bounds its wait for the writer, and `makeVideoPixelBuffer` unlocks the buffer on every path after a successful lock. `PetShareMovieWriter` keeps two narrow concurrency exceptions instead. `MovieWriterState` is `@unchecked Sendable` because AVFoundation's writer classes are non-Sendable: the class creates them once, mutates them only on the serial export queue, and keeps every mutable counter behind an `OSAllocatedUnfairLock`, so the waiting caller's terminal reads are synchronized with the queue's exactly-once terminal transition. Its `@preconcurrency import AVFoundation` documents that same boundary; the public `PetShareExporter` file imports AVFoundation normally. `AppSettings` is the other `@unchecked Sendable` type: `UserDefaults` is documented as thread-safe and is its only stored state, so the conformance only stands in for `UserDefaults` not being marked `Sendable`. The image test helper also has two exact pointer-use exceptions: it allocates a buffer and releases it with `defer`, and passes that buffer to Core Graphics.

`KeyboardMonitor` has four exact `Unmanaged` exceptions for its Core Graphics event-tap bridge. `AppDelegate` retains the monitor, `stop()` removes the run-loop source and invalidates the tap before clearing it, and the callback uses unretained conversions to avoid creating an ownership cycle while returning the event with the callback API's expected ownership.

## What static checks cannot prove

Syntax checks cannot prove that every Core Foundation or C API resource is released on every path, that a lock is balanced across all exits, or that a writer always completes. Those guarantees need targeted tests and runtime leak tools. Swift 6 strict concurrency and the compiler's enum exhaustiveness diagnostics remain part of the normal build; the explicit default-case check prevents a new catch-all from hiding future cases.

The checker intentionally does not ban every `Any` or `AnyObject`: Apple APIs and Objective-C bridges use these types legitimately. It checks syntax, not resolved symbols or ownership semantics; it is a review gate, not a proof of safety. Review type-erasure additions in context and prefer concrete types or a named protocol when possible.
