# Live GUI QA before the next refactor

## Provenance and limits

- Product revision: `85b96a84a7a919165078c503396e2c2d152500f7` (merged main).
- Session date: 2026-10-20 (UTC); Apple Silicon, macOS 27.0.1 (`26A434`).
- Ad-hoc signed Release development variant: `dev.nyatinte.waddly.qa-loach.development`.
- Isolated preferences/images; no production preferences or pet images changed. The user granted
  Input Monitoring to the development variant during this session. That grant was not reset.
- **Live GUI automation**, not a human mouse/trackpad or VoiceOver walkthrough. Orca supplied
  accessibility actions, synthetic keyboard events, accessibility snapshots, and ScreenCaptureKit
  window captures. CoreGraphics pointer events supplied hover and opened the non-key pet panel's
  context menu because Orca's coordinate-click focus guard rejected that panel.
- Outcomes below were read back from the live window, not inferred from an action's success status.
  These are real window screenshots, not `cacheDisplay` fixtures. They prove only the captured states.
- Japanese/dark was exercised first, then English/dark using development-only `AppleLanguages`.
  A development-only light-appearance preference did **not** change the visible appearance; no
  light-mode pass is claimed. Temporary appearance/keyboard preference overrides were removed.
- The clipboard was replaced with QA image/text data for copy/paste checks. No pre-existing
  clipboard payload was read or saved. No post/composer was opened and nothing was uploaded.

## Executed checks

`Observed` means the specified result was visible in the running app. It does not certify the whole
issue, accessibility, or physical-device interaction.

| ID | Issue | Steps | Observed result | Evidence |
| --- | --- | --- | --- | --- |
| S1 | #111, #124 | Fresh variant → PNG option → native picker; select `Tests/WaddlyCoreTests/Fixtures/nyatinte-bot-3x3.png` through Go to Folder | Staged preview and 768 × 768 / 256 × 256 metadata; Continue enabled | `setup-start-ja-dark.png`, `setup-staged-ja-dark.png` |
| S2 | #124 | Cancel the staged setup import; cancel the discard sheet | Discard sheet appears; cancelling it retains the valid draft and metadata | `setup-discard-ja-dark.png`; live snapshot after dismissal |
| S3 | #110, #111 | Continue → Input Monitoring; choose Set up later | Ready explicitly says monitoring is not configured and typing reactions remain unavailable | `setup-skipped-permission-ja-dark.png` |
| S4 | #110, #111 | After the user's grant/relaunch, reopen Setup Guide → Next | Functional-ready monitoring page, then Return → completed; another Return closes setup | `setup-permission-ready-en-dark.png`, `setup-complete-en-dark.png` |
| H1 | #108 | Open Share from the pet context menu; move pointer over video copy, image copy, Play and Post separately | Copy/Post backgrounds tint; Play background darkens; no apparent layout shift | `share-ready-ja-dark.png`, `share-copy-hover-ja-dark.png`, `share-image-hover-ja-dark.png`, `share-play-hover-ja-dark.png`, `share-post-hover-ja-dark.png` |
| H2 | #108, #109 | Activate Copy video and Copy image | Separate inline video/image success messages, unchanged button labels | `share-copied-ja-dark.png` |
| H3 | #108, #109 | Play, then Pause | Poster replaced by the movie; accessible action changes to Pause, then back to Play | `share-playing-ja-dark.png`, `share-play-hover-ja-dark.png` |
| H4 | #111 | Relaunch development variant with English language; reopen Share | English labels fit at the same 700 × 438 pt window size | `share-ready-en-dark.png` |
| C1 | #124 | Change Character → ⌘V using the image copied from Share | Valid clipboard candidate with dimensions and preview | `character-pasted-ja-dark.png` |
| C2 | #124 | Replace clipboard with QA text, then ⌘V | Inline no-image error; valid candidate and Apply remain available | `character-paste-error-ja-dark.png` |
| C3 | #124 | Put the repository PNG on the clipboard; activate Paste | Error clears, valid clipboard candidate remains, dimensions shown | live snapshot after retry |
| C4 | #124 | Close dirty Change Character → Discard; reopen from pet context menu | Dirty close prompts; reopened window shows committed pet without clipboard-source metadata or error | `character-reopened-ja-dark.png`; live discard-sheet snapshot |

Screenshots are in [`images/live-qa-85b96a8/`](images/live-qa-85b96a8/).
H2 proves the application's copy outcome; C1 additionally exercises image paste into the actual
import window. External video paste compatibility was not tested. S4 does not reconstruct the
user's TCC handoff or verify every intermediate granted-but-not-receiving state.

## Not passed / not executed

| Check | Status and next step | Tracker |
| --- | --- | --- |
| Tab / Shift-Tab / Space traversal and visible focus | **Unverified.** Synthetic Tab in Setup and Share left the reported focus on the window; no successful control traversal was established. System Settings showed Keyboard Navigation enabled. This is an observation, not a diagnosed application defect or proof of a keyboard pass. Reproduce with a physical keyboard before changing key-loop code. | #108, #111, #124 |
| Keyboard Navigation shortcut | Orca rejected Control-F7 as unsupported. No global keyboard setting was changed. The development-only keyboard override did not establish traversal and was removed. | #111 |
| Accessible names in Setup/import | Orca's tree omitted names on several SwiftUI buttons despite visible captions and source accessibility labels. Share AppKit button names were present. Distinguish an observer limitation from a real VoiceOver defect before adding redundant labels. | #111, #124 |
| Light mode / increased contrast / Reduce Motion | Not verified; screenshots are dark only. | #108, #111, #124 |
| VoiceOver and physical mouse/trackpad | Not run. Synthetic hover and AX activation are not physical-device acceptance. | #108, #111, #124 |
| Finder-to-window drag, multiple files, minimization, advanced editor, narrow labels | Not run in this session. | #124 |
| Share generation/copy failure, Retry, disabled and held-press states, Post action | Not injected or exercised in the live app; source/tests are not a live pass. | #108, #109, #111 |
| Import save failure / retry and whole-process close/import memory | Not run in this session. | #124 |

**Closure decision:** keep #108, #111 and #124 open. This session reduces their outstanding QA,
but does not complete their remaining acceptance criteria. The same evidence advances #109/#110
without certifying their complete journeys. Do not add duplicate issues for the unverified items.

## Follow-up: native keyboard baseline

A temporary, independent Swift 6 AppKit executable (no Waddly imports) displayed a titled window
with an ordinary `NSButton` and a borderless `NSButton` in an `NSStackView`. In the live window,
`NSApplication.isFullKeyboardAccessEnabled` reported `false` and the standard button's
`canBecomeKeyView` reported `false`. Orca's synthetic Tab again left accessibility focus on the
window. The system Keyboard Navigation UI had shown enabled, while the global
`AppleKeyboardUIMode` preference was `1`; these observations do not establish why the runtime
reported otherwise. No global keyboard preference was changed.

This reproduces the observation without Waddly's custom controls or key-loop code, so it is not
evidence for a Waddly-specific key-loop patch. The unresolved boundary is macOS configuration/runtime
versus synthetic input/observation. Next: compare physical Tab in this native baseline and Waddly on
the same Mac before changing application code. The temporary probe is not a product change or a
substitute for acceptance, and its capture is not included in the 17 product screenshots.

## Build and test evidence

- `mise run dev:install` with the isolated suffix/directory: passed (includes Release build).
- `mise run build`: passed; SwiftFormat/localization checks and strict SwiftLint passed, signed app produced.
- `mise run test:guard`: passed all deterministic completion-guard checks.
- `mise run test`: **failed**, not a full pass. Core completed with 63 tests in 4 suites and one
  known issue. The App run stopped after starting
  `SetupWizardCharacterImportTests.cancellingAnUntouchedSharedScreenLeavesWithoutPrompting`.
  The guard reported `2 Swift Testing run(s) started but only 1 reported completion`.
- No retry-until-green, skipped tests, or focused-subset substitution. Root cause remains #131;
  this run does not establish a crash location or the cause of the early exit.
- No Swift/product behavior changes were made for this QA report.
