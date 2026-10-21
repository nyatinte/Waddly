# Disabled native-menu reasons

For #111. These are **native menu content-view renders, not OS screenshots or physical-input QA**.

## Contract

The existing validation guards are unchanged. Disabled Change Character needs completed setup;
Share needs a complete character, not completed setup; neither presence switch may remove the last
entry point. Both-off recovery still permits either switch. Validation assigns a localized standard
`NSMenuItem.toolTip`, and, on macOS 14.4+, the same reason in the standard `subtitle`. Enabling the
command clears both. Native menu copies preserve these properties independently.

On macOS 14.0–14.3 only the help tag is installed. Its visible hover behavior is **not verified**;
do not treat installing a property as proof of a discoverable explanation on those systems.

## Provenance and scope

- Before: `16bf69b` (merged main before this change).
- After product source: `e3288a561b131d0c99c6af39bb1e1d34f85e9195`.
- Same archived standalone runner, optimized Swift 6 compilation, unchanged WaddlyCore sources,
  ad-hoc signed temporary bundles (`dev.nyatinte.waddly.qa111menu`), and source-specific JA/EN resources.
- The runner replaces only `AppMain.swift`, constructs the actual `AppDelegate` and status menu,
  and opens it with native `NSMenu.popUp`. The presence submenu is opened separately, **not**
  through a pointer-driven cascading-menu journey.
- Same isolated configuration: no images, incomplete setup, Dock off / menu bar on. Therefore
  Change Character and the last Menu Bar switch are disabled. No images are imported or saved.
  Share's missing-character guard is covered by tests, not these status-menu renders.
- Both languages × light/dark × status/presence menus = eight captures per source. The native
  popup window's content view is captured using `bitmapImageRepForCachingDisplay` / `cacheDisplay`
  while menu tracking is active. This is not a hand-built menu or a restyled HTML reproduction.
- Each run reached `PROBE_COMPLETED 8`; exact dimensions, validation readback and completion
  markers are retained in `before/run.txt` and `after/run.txt`. Native menu sizes change to fit the
  new subtitle; these are not pixel-aligned screenshots. Tracking/highlight state is not a
  controlled physical-hover comparison.
- Both-off and all other presence combinations, already-copied context/status menus, setup
  progress changes, and enabling/clearing stale explanations use actual `NSMenu.update` in
  `MenuDisabledHelpTests`. Separate resource checks resolve the exact Japanese and English copy;
  the normal command-line test host does not bundle app localization resources.
- A UUID defaults suite is removed at exit. No event tap, permission request, production image,
  production preference, or system accessibility setting is changed. Production Waddly was left
  running; all renderer processes exited.

## Comparisons

| State | Before | After |
| --- | --- | --- |
| EN / light, status | [image](before/en-light-status-menu.png) | [image](after/en-light-status-menu.png) |
| EN / dark, status | [image](before/en-dark-status-menu.png) | [image](after/en-dark-status-menu.png) |
| JA / light, status | [image](before/ja-light-status-menu.png) | [image](after/ja-light-status-menu.png) |
| JA / dark, status | [image](before/ja-dark-status-menu.png) | [image](after/ja-dark-status-menu.png) |
| EN / light, presence | [image](before/en-light-presence.png) | [image](after/en-light-presence.png) |
| EN / dark, presence | [image](before/en-dark-presence.png) | [image](after/en-dark-presence.png) |
| JA / light, presence | [image](before/ja-light-presence.png) | [image](after/ja-light-presence.png) |
| JA / dark, presence | [image](before/ja-dark-presence.png) | [image](after/ja-dark-presence.png) |

Environment, runner/build recipe and image hashes are archived alongside this file. To reproduce
from a checkout containing both commits, copy the archived runner and script to their `/tmp`
paths, compile the unchanged core into `dist/qa111-menu/core` as in `macos/profile-image-app.sh`,
and run the archived shell recipe from the repository root. The recipe archives each app revision
and copies its own localization resources; it does not build against uncommitted app changes.

## Remaining acceptance

Visible tooltips on macOS 14.0–14.3, actual menu invocation/traversal with a physical keyboard,
spoken VoiceOver, increased contrast and small-display behavior remain unverified under #111.
The popup renderer and native validation tests do not close that issue or establish those cases.
Full `mise run check` passed: 244 tests / 26 suites, one pre-existing Core known issue, and signed
arm64 Release build. An initial format check, then a test complexity check and a shifted existing
safety-allowlist location were corrected before the successful full validation; no test suite,
completion guard, product timeout, or validation threshold was weakened.
