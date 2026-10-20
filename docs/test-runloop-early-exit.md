# Swift Testing early exit: AppKit tracking versus async main (#131)

## Reproduced cause

Baseline: `060aa79e2a6cda4d9682eaec5a3f250564e47ce0`; Apple Silicon, macOS 27.0.1 (`26A434`), Swift 6.4 (`swiftlang-6.4.0.34.1`). Full local tests consistently completed Core (63 tests) but exited during App tests without a completion footer. The unchanged completion guard correctly rejected the raw process exit of 0.

Temporary native interposition of `CFRunLoopPerformBlock`, `CFRunLoopStop`, `CFRunLoopRun` and `exit` captured the termination, without a debugger attached. LLDB runs completed instead, so those were not accepted as reproductions. Selected native symbols from the failing process, condensed with addresses omitted:

```text
WindowServer event thread schedules a block for the main run loop:
  HIToolbox: PushToCGEventQueue
  HIToolbox: PullEventsFromWindowServerOnConnection
  HIToolbox: MessageHandler
  AppKit: _NSEventThread

That block executes on the outer async-main loop:
  CFRunLoopStop(main)
  __CFRunLoopDoBlocks
  __CFRunLoopRun
  CFRunLoopRun
  libswift_Concurrency: CFMainExecutor.run()
  libswift_Concurrency: swift_task_asyncMainDrainQueueImpl

CFRunLoopRun returns; the concurrency runtime calls exit(0).
The App test run has not completed.
```

The last-started test (`closingTheWizardConfirmsDiscardOfADirtySharedDraft`) is not a crash location. The asynchronous wakeup arrives after earlier `NSButton.performClick` calls entered AppKit's synchronous event-tracking loop. Captures also showed such a wakeup being consumed correctly *inside* `NSButtonCell.performClick`; a later wakeup reached the outer Swift loop instead. This is a native event-loop / async-main integration failure, not evidence of a Waddly window-close defect or compiler miscompilation.

Upstream source corroborates the runtime behavior: [CFMainExecutor.run](https://github.com/swiftlang/swift/blob/6324025b2419fbbb6e0b6d6d7118e50d58b033a4/stdlib/public/Concurrency/CFExecutor.swift) calls `CFRunLoopRun` once; [drainMainQueue](https://github.com/swiftlang/swift/blob/6324025b2419fbbb6e0b6d6d7118e50d58b033a4/stdlib/public/Concurrency/ExecutorImpl.swift) exits with 0 if the executor returns. These references explain the design; they are not a claim that this upstream commit built the installed runtime.

Full local trace and diagnostic-only interposer remain under ignored `dist/diagnostics/131/`. The captured trace SHA-256 is `cfa0f3019af7bed5ed1cd32ef434c34f9c54b3f00a22bfbf304b6f1bd7a763a2`; interposer source SHA-256 is `b25154c15727f9dec389ca25683788ecbefeeca6865f9414142c3088100927ae`. Neither is loaded by normal tests or the app.

## Independent minimal reproduction

`Tools/probe_appkit_runloop.swift` imports AppKit only, not Waddly or Testing. It uses its own fully transparent windows, no synthetic input events, imported images, production preferences or permission requests. Compile once and run each mode once:

```sh
swiftc -swift-version 6 -parse-as-library Tools/probe_appkit_runloop.swift \
  -o /tmp/waddly-runloop-probe
/tmp/waddly-runloop-probe --perform-click > /tmp/waddly-runloop-native.log
/tmp/waddly-runloop-probe > /tmp/waddly-runloop-action.log
grep PROBE_COMPLETED /tmp/waddly-runloop-action.log
```

On the affected local runtime:

| Mode | Raw exit | Completion evidence |
| --- | --- | --- |
| `--perform-click` | 0 | Only `PROBE_STARTED mode=performClick`; no cycle/completion marker |
| Default target/action | 0 | All ten cycles and `PROBE_COMPLETED actions=10` |

**Do not use exit status alone to judge the reproducer.** A fixed/different runtime may complete both modes; failure of the native mode is not required on every platform. The action mode must complete and assert exactly ten delivered actions. A preliminary window-only probe also completed all ten cycles: opening windows alone did not establish the cause.

## Narrow fix and verification

- Action-wiring tests now call `sendTestAction` on the **actual control**: require enabled state, then assert that `NSControl.sendAction` routes its configured target/action. They do not call controller callbacks directly or silently ignore disabled/unwired controls.
- Replace all nine `performClick` calls in App tests. The checkbox uses AppKit's `setNextState()` before sending its action; both state transitions and preview-background assertions remain. This tests state/action wiring, **not the physical gesture or automatic cell tracking**.
- Add a regression that sends the actual button action, yields with a real transparent window, closes it and yields again, verifying one delivered action.
- Keep all existing tests, native window/sheet checks, cancellation/recovery assertions, CLI options, macro-plugin path and completion guard. No retry, suite isolation/skip, private runtime override, injected library or production code change.

After the fix, the first full `mise run test` completed **63 Core tests / 4 suites** (one known issue) and **174 App tests / 20 suites**: **237 tests / 24 suites**, with both start markers matched by completion footers. A subsequent full `mise run check` also completed all 237 tests, format/lint/complexity/safety, the deterministic completion-guard harness, and the signed arm64 Release build. These are genuine full selected runs after a justified change, not focused subsets or retries until green. No instrumentation was loaded in these validation runs.

The previously stale release-PR criterion was checked against #138's actual head `bafcdbd5c302de3722ad4c7a9269adaac0f92b5f`: [its final full CI](https://github.com/nyatinte/Waddly/actions/runs/39392234426/job/118526276049) completed 236 tests / 24 suites (one known issue), then built Release; #138 was already merged as `ba38a08`. This corrects the old tracker status; it does not claim that the new fix was in that release source or waive #143's separate export-timeout gate.

Physical mouse/keyboard, held-press tracking and VoiceOver acceptance remain in **#111**. This reproduces and addresses the current local early-exit mechanism; it does not retroactively prove that every historical incomplete CI run had the same native cause. The fail-closed guard remains necessary for any other termination mechanism. **#143** and memory acceptance **#98** remain independent.
