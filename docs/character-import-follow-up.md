# Character import: advanced editing and lifecycle follow-up (#124)

## Scope and provenance

This is a bounded follow-up to [the earlier live session](live-qa-85b96a8.md), not a fresh pass of
all of #124. Work is split with `gh stack`: callback/store regression coverage (#139), native
frame-action help and pose-aware labels (#140), then this evidence layer. None closes #124.

- Session: 2026-10-20, Apple Silicon, macOS 27.0.1 (`26A434`), Swift 6.4.
- Before product sources: merged main `ac3fc14da743e4d47b814ac8d87172f485d9c364`.
- After product sources: `ffa65a56fdb2593e2b460308287b6754dd1da091`, including regression
  `884f48a9734a910dfab2200db937935baa2a1bbc`. Only the six files in #140 change product help/labels.
- Ad-hoc signed Release variant `dev.nyatinte.waddly.qa124.development`, built with
  `WADDLY_DEVELOPMENT_SUFFIX=qa124.development WADDLY_DEVELOPMENT_DIR="$PWD/dist/qa124" mise run dev:install`.
- Separate preferences and `Waddly-qa124.development/PetImages` storage. The production app, pet,
  preferences and permission grants were not changed. No Input Monitoring permission was requested.
- JA then EN via development-only `AppleLanguages`; all captures are **dark**. For the last setup
  capture only, the QA variant's `setupWizardSeen=false` and `setupStep=0` reopened its Pet step on
  the already saved custom character. That is not a new first-run completion or resume acceptance.
- Actual visible windows, native accessibility actions and synthetic pointer input; **not a human
  keyboard/VoiceOver/physical-pointer walkthrough**. Orca captured windows using ScreenCaptureKit.
  An independent temporary Swift helper read `AXAttributedDescription`, `AXHelp`, `AXEnabled` and
  `AXMinimized`, and performed `AXPress` by the exact current control label. These are OS
  accessibility operations, not calls to Waddly's model, callbacks or persistence functions.
- No clipboard payload was read or backed up for this follow-up. Only repository/generated QA
  images were chosen. Finder/open-panel captures containing unrelated filenames are not published.

## Observations

| ID | Live action and read-back | Outcome | Evidence in `images/character-follow-up/` |
| --- | --- | --- | --- |
| A1 | Setup → PNG path → native picker → repository `assets/examples/nyatinte-bot-3x3.png` → advanced editor | Four rows with 2 Idle / 4 Typing / 2 Sleep / 1 Enter. Native setup Continue committed the initial sheet; monitoring was skipped with the explicit not-configured warning. | `editor-before-setup-ja-dark.png` (before sources) |
| A2 | Open Change Character on the saved pet → advanced editor | Same four categories; read native labels/help in JA, then EN. Last Enter removal is disabled and exposes the minimum-frame reason. First/last movement controls expose their boundary reason. | `editor-after-change-ja-dark.png`, `editor-after-change-en-dark.png`, `native-ax-{ja,en}.json` |
| A3 | Remove Idle frame 1 and move Typing frame 1 right via native AX actions → Done → minimize parent → invoke Change Character again from pet menu → reopen editor | One smiling Idle remains; Typing's first two thumbnails are swapped. Native `AXMinimized` changes 1 → 0. Draft edits survive refocus; no reload to the saved two-Idle baseline. | `editor-after-minimize-restore-ja-dark.png`, `minimize-native.txt` |
| A4 | Done → parent Cancel → cancel the discard alert → reopen editor | Dirty-only discard alert is visible; cancelling it keeps the one-Idle/reordered draft. | `discard-advanced-edits-ja-dark.png`; native AX read-back during the session |
| A5 | Parent Cancel → Discard → open Change Character again → advanced editor | Saved two-Idle character and original Typing order return. The staged deletion/reorder were not committed. | `editor-after-discard-reopen-ja-dark.png` |
| A6 | EN Change Character → remove Idle frame 1 → Done → Apply | Character window closes. The isolated on-disk manifest contains 1 Idle / 4 Typing / 1 Enter / 2 Sleep. | `applied-manifest.json`; native window-list read-back |
| A7 | Relaunch the variant → reopen setup Pet with the QA-only progress overrides described above → Change image → advanced editor | The saved **custom** one-Idle character is loaded in the other host without selecting its original sheet. No source dimensions are invented in the shared import screen. | `setup-saved-custom-frames-en-dark.png` |

The before screenshot is the **Setup host**, while the first after screenshot is **Change Character**;
they are not a matched pixel-diff pair. Captures show actual rows/layout and the draft transitions,
not the contents of a hover tooltip. The new help text is verified by native `AXHelp` read-back;
a visible hover popover and its VoiceOver delivery are **not** claimed as passed.

## Accessibility observer finding

Orca's ordinary tree still omits several SwiftUI names. Direct native inspection finds them in
**`AXAttributedDescription` as attributed strings**, rather than ordinary `AXTitle`/`AXDescription`.
For example the frame action exposes `Enter — Remove image 1`, `AXEnabled=0`, and
`AXHelp=Keep at least one image in each pose.`; JA exposes the corresponding localized values.
The selected 31 editor-button records per language are checked in without pointer addresses or
unrelated window contents.

This resolves the earlier *observation gap*, not VoiceOver acceptance. The patch adds pose context
to existing labels; it does not add a parallel accessibility layer to work around the observer.
Some Orca sheet coordinate actions were rejected by its focused-window guard or reached another
control; only later semantic native actions with the recorded read-back count as observations.

## Not passed / remaining work

- **Finder-to-window/category drag:** synthetic cross-window attempts did not establish receipt by
  Waddly or a valid hover state. One attempt moved the generated sheet inside Finder; the exact
  hash-matched QA fixture was restored to its temporary folder. No drag pass or Waddly drag defect
  is inferred. Use a physical drag or a verified cross-window driver for single/multiple/invalid
  files, preview/body hover, cancellation and advanced-category precedence.
- **Keyboard/VoiceOver:** physical Tab/Shift-Tab/Space/Return/Escape, focus rings, spoken grouping,
  validation announcements and image ordering remain unverified. See the native keyboard baseline
  in the earlier report; do not patch the key loop from synthetic input alone.
- **Appearance/layout:** light, increased contrast, Reduce Motion, smaller display/long-label
  geometry and dynamic text remain unverified. These dark JA/EN captures are not that acceptance.
- **Failures:** no live disk-full/save-failure injection or retry. The model/store tests remain
  automated evidence, not a native failure walkthrough.
- **Memory:** no new budget pass. [The corrected acquisition/close baseline](measurements/character-lifecycle-20261020/follow-up/README.md)
  verifies fresh acquisitions and controller/model release, but residual rendering/purgeable/RSS
  growth is not fully classified and there is no matched historical comparison. #98/#95 stay open.
- **Full local tests:** #131 remains. The incomplete runs below stay failures; no subset substitutes
  for a full pass. Keep #124 open until its remaining acceptance is genuinely exercised.

## Verification

- `./macos/test.sh --no-parallel --filter AnimationSettingsTests`: 7 tests completed, including
  both Apply/discard cases of the new parameterized callback/store regression.
- Layer 1 `mise run test`: **failed closed**, two Swift Testing runs started and one completed;
  last started test was `closingTheWizardConfirmsDiscardOfADirtySharedDraft`.
- Layer 2 `mise run check`: format, localization generation, strict lint, complexity, safety and
  completion-guard fixtures passed; full tests **failed closed** with the same 2/1 mismatch after
  `anUntouchedWizardCanCloseWithoutConfirmation` started. No check/full-suite pass is claimed.
- `mise run build` separately passed for each Swift-change layer; signed Release variant installation
  also passed. CI results, when available, are separate evidence from these failed local runs.

## Repeat the bounded checks

Build the isolated variant with the command above; launch the installed bundle under `dist/qa124/`.
Use the repository PNG in the native picker and finish or skip Input Monitoring without granting
permission. In Change Character, open the advanced editor, remove the first Idle frame, move the
first Typing frame right, and return with Done. Minimize, reopen through the menu, and inspect the
editor again. Cancel the parent, first keep changes, then discard and reopen. Finally repeat the
one-Idle edit and Apply, relaunch, and inspect the saved frames from either host.

For native accessibility inspection, use Accessibility Inspector or
`AXUIElementCopyAttributeValue` on the target variant's current controls for
`AXAttributedDescription` (cast to `NSAttributedString` and read `.string`), `AXHelp` and `AXEnabled`;
read `AXMinimized` on the character window before/after refocus. Do not equate a successful
`AXPress` return with an observed result. Refresh the UI and read back the changed state.
