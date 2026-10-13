# Swift safety checks

The required `mise run check` validation runs SwiftLint in strict mode and the SwiftSyntax-based `swift-safety-check`. The syntax checker rejects forced casts, forced try, forced unwraps, unsafe casts, raw pointer/Unmanaged types, unchecked concurrency annotations, actor assumptions, unbounded zero-argument `wait()`, and unapproved switch defaults. Its fixtures prove each rule rejects a deliberately unsafe Swift sample.

## Narrow baseline exceptions

`Tools/SwiftSafetyCheck/Allowlist.json` contains only existing source locations that were reviewed while introducing the check. Each entry is tied to a rule and exact line; moving the code requires reviewing and updating the entry. New uses fail CI. Keep any new exception narrow, explain the invariant in the change, and require review.

The current semaphore wait and pixel-buffer ownership path are already tracked for remediation in [#96](https://github.com/nyatinte/Waddly/issues/96). The image test helper also has two exact pointer-use exceptions: it allocates a buffer and releases it with `defer`, and passes that buffer to Core Graphics.

`KeyboardMonitor` has three exact `Unmanaged` exceptions for its Core Graphics event-tap bridge. `AppDelegate` retains the monitor, `stop()` removes the run-loop source and invalidates the tap before clearing it, and the callback uses unretained conversions to avoid creating an ownership cycle while returning the event with the callback API's expected ownership.

## What static checks cannot prove

Syntax checks cannot prove that every Core Foundation or C API resource is released on every path, that a lock is balanced across all exits, or that a writer always completes. Those guarantees need targeted tests and runtime leak tools. Swift 6 strict concurrency and the compiler's enum exhaustiveness diagnostics remain part of the normal build; the explicit default-case check prevents a new catch-all from hiding future cases.

The checker intentionally does not ban every `Any` or `AnyObject`: Apple APIs and Objective-C bridges use these types legitimately. Review type-erasure additions in context and prefer concrete types or a named protocol when possible.
