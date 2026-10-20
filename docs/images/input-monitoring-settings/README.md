# Post-setup Input Monitoring entry: render evidence (#146)

## Paired content-view renders

These are **AppKit/SwiftUI content-view renders, not OS screenshots or live menu acceptance**.
They use the real application sources with an alternate, standalone entry point archived as
[`render.swift.txt`](render.swift.txt). No product/test-runner instrumentation is installed.

- Before source: `2dcb8ea88d587aeb19059d7b51d1e5c727fb35fd`.
- After source: `7dc6c877fbe3479f9cfaa2ba18088dba0f187b0f`.
- Environment: macOS 27.0.1 (`26A434`), Apple Silicon, Swift 6.4.
- Same stored-character fixture: `assets/examples/nyatinte-bot-3x3.png`.
- State: completed setup, no saved step; missing Input Monitoring permission is injected, not requested.
- Before: the controller constructed by the old completed-user menu action starts at Pet.
- After: the completed-user menu constructs monitoring settings directly, with no progress indicator,
  Back, Later, or onboarding completion action; Close remains available.
- Each pair uses the same language, Aqua/darkAqua, 820 × 520 pt content bounds, and 1640 × 1040 px
  output. Title bar, menu, pointer, and desktop are deliberately outside the render.
- Source archives are compiled with `swiftc -O -swift-version 6`; the after entry point additionally
  uses `-D MONITORING_SETTINGS_CHANGED`. Both runs reached `CAPTURE_COMPLETED` after writing four PNGs.
- Preferences use disposable UUID suites, the presenter keeps windows transparent, permission/settings
  actions are injected no-ops, and the runner does not read or modify production images or settings.

| Language / appearance | Before | After |
| --- | --- | --- |
| English / light | [before/en-light.png](before/en-light.png) | [after/en-light.png](after/en-light.png) |
| English / dark | [before/en-dark.png](before/en-dark.png) | [after/en-dark.png](after/en-dark.png) |
| Japanese / light | [before/ja-light.png](before/ja-light.png) | [after/ja-light.png](after/ja-light.png) |
| Japanese / dark | [before/ja-dark.png](before/ja-dark.png) | [after/ja-dark.png](after/ja-dark.png) |

To reproduce: copy the archived entry point to a `.swift` file, archive each revision's `Sources` to
separate temporary directories, compile `Sources/WaddlyCore/*.swift` as static module `WaddlyCore`,
then compile each archive's `Sources/WaddlyApp/*.swift` except `AppMain.swift` with the entry point and
that module. Run each executable with `REPOSITORY_ROOT OUTPUT_DIRECTORY`. The repository supplies the
same fixture and localization resources to both runs. The explicit `#if` only selects the respective
controller initializer; application rendering code is taken from each source archive.

## Native attempt and its limits

A separately installed development app, `dev.nyatinte.waddly.qa146.development`, used its own preferences
and `Waddly-qa146.development/PetImages` directory. Its initial English guide was accessible and the
sample → Next → Set up later → Show on desktop sequence reached `setupWizardSeen = true`, with no
saved `setupStep`. Native AX menu readback then contained both **Change Character…** and
**Set Up Input Monitoring…** instead of Setup Guide.

After attempting the monitoring menu action, the GUI tool reported a WindowServer entry titled
**Set up Input Monitoring**, but could not obtain an AX window. Its permission status reported both
Accessibility and screenshots granted. A restarted isolated app had the same observation limitation;
a missing AX window does **not** establish a product root cause or a successful interaction.
A legacy helper also crashed on its own missing-window force unwrap; the application stayed alive.
Thus these attempts are **not** credited as live monitoring-window, closing, keyboard, permission
handoff, VoiceOver, or drag-and-drop acceptance. No permission grant or system preference change was
made to work around the limitation. The isolated app was stopped, and saved-image file hashes were
unchanged across the monitoring-entry attempts.

The regression suite covers real menu target/action wiring, setup/data preservation, both languages,
all four injected readiness states, and existing recovery actions. It is not physical input or spoken
VoiceOver acceptance; those remain in #111. The paired renders demonstrate default-layout appearance
only, not a full end-to-end native journey or actual permission recovery.
