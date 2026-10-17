# Waddly UX interaction audit and QA matrix

For [#111](https://github.com/nyatinte/Waddly/issues/111). A compact, contributor-maintainable
audit of Waddly's entry points, per-control action/state contracts, and a manual QA matrix. It is
intentionally **not** a design system and it adds no runtime behavior.

## Evidence status — read first

Every claim below is one of two kinds, kept apart throughout:

- **Source-audited** — read directly from the code at the revisions in the table. Describes current
  behavior.
- **Manual-unverified** — needs a real GUI session (VoiceOver, System Settings, live keyboard).
  **Nothing here claims these were run.** Do not tick a manual row until it is executed on a Mac.

| Source | Revision audited | Delta relevant to this audit |
| --- | --- | --- |
| `main` (base of this document) | `f1918a0` | current sources for every surface |
| [#94](https://github.com/nyatinte/Waddly/issues/94) setup feedback, PR [#118](https://github.com/nyatinte/Waddly/pull/118) | `agent/issue94-setup-feedback` @ `86dfce5` | inline setup failure/browser feedback, one accessibility announcement per error transition, preview backdrop follows appearance, `docs/setup-wizard-qa.md` |
| [#95](https://github.com/nyatinte/Waddly/issues/95) editor, PR [#116](https://github.com/nyatinte/Waddly/pull/116) | `agent/issue95-swiftui-editor` @ `a38452f` | Animation Settings → SwiftUI; editor model released on close |
| [#96](https://github.com/nyatinte/Waddly/issues/96)/[#99](https://github.com/nyatinte/Waddly/issues/99) share, PR [#115](https://github.com/nyatinte/Waddly/pull/115) | `agent/issue96-99-export-cancellation` @ `4f6398e` | closing Share cancels the in-flight export and removes partial temp assets |

[#109](https://github.com/nyatinte/Waddly/issues/109) (Share flow) and
[#110](https://github.com/nyatinte/Waddly/issues/110) (first-run journey) are in progress. Their
contracts are marked **proposal** here, never verified implementation.

Screenshot evidence: only the native renders committed on the PR branches are linked (§7). They are
AppKit `cacheDisplay` renders, not screen captures, and prove default-font layout only.

## 1. Entry points and window lifecycle (source-audited)

| Entry point | Trigger | Result | Close / reopen |
| --- | --- | --- | --- |
| Pet panel | left-drag | moves the borderless panel; origin saved and clamped to visible screens | pet stays on the desktop |
| Pet panel | right-click | `makePetContextMenu()` = copy of the status menu with “Share Pet” inserted first | rebuilt per open; `menuWillOpen` refreshes state |
| Pet panel | drop a PNG | imports through the pet-image path (writes only after validation) | — |
| Dock icon | click | setup complete → `bringPetToFront()`; otherwise `showSetupWizard()` | never opens the editor |
| Menu bar item | click | opens the status menu; tooltip reads reaction state (paused / active / permission) | menus rebuild after a language change |
| Status/pet menu | “Setup Guide…” | opens or resumes the guide | close keeps the saved step |
| Status/pet menu | “Animation Settings…” | opens the editor (disabled until setup is complete) | close clears content; reopen rebuilds |
| Status/pet menu | “Share Pet” (pet menu only) | opens the Share window | close cancels export and deletes temp assets (#115) |

Setup navigation contract:

- Steps **Pet → Input Monitoring → Ready**. The step indicator shows progress and hides on Ready.
- **Back** exists on Input Monitoring and Ready; Pet has none.
- **Next** is disabled on Pet without an image, and on Input Monitoring until permission is
  genuinely *receiving keys* (not merely granted). It is the window's default action.
- **Set up later** appears only while monitoring is not ready and lands on Ready with an explicit
  warning — it never impersonates success.
- Closing mid-way keeps `setupStep` and leaves `setupWizardSeen` cleared, so a relaunch or Dock click
  resumes. Finishing clears the saved step. `isSetupComplete` requires image + seen + cleared step,
  so a finished guide cannot trap the user (`AppDelegate.opensSetupOnLaunch`).
- The wizard is a fixed 820 × 520 pt non-restorable window (`SetupMetrics`), so a stale restored
  frame cannot reflow the layout.
- The permission guide follows the System Settings window until the user moves it
  (`PermissionService` + `PermissionGuidePlacement`).

## 2. Interactive components: action + state contract

Legend: **Y** native/distinct, **~** partial or weak, **N** absent (gap), **—** not applicable.

### 2a. Preferences menus (status menu + pet context menu)

AppKit supplies hover, press, keyboard focus, and radio/check rendering for `NSMenuItem`. The gaps
are about *reason* and *outcome*, not plumbing.

| Control | Action | Disabled | Success | Error |
| --- | --- | --- | --- | --- |
| Pause / Resume reactions | toggles animation and the key tap | — | title flips | — |
| Display size ▸ Small/Medium/Large | resizes panel, saves origin | — | radio state syncs | — |
| Typing motion ▸ Off/Weak/Strong | applies amplitude | — | radio state syncs | — |
| Breathing animation | toggles idle breathing | — | check state | — |
| Language ▸ System/日本語/English | switches the string catalog | — | radio state; menus rebuild on next open | — |
| Show in ▸ Dock / Menu Bar | toggles presence | **N: greyed when it would hide both entry points, with no reason shown** | check state | — |
| Animation Settings… | opens the editor | **N: greyed until setup is complete, with no reason** | — | — |
| Setup Guide… | opens or resumes the guide | — | — | — |
| Launch at Login | register/unregister `SMAppService` | — | check reflects real status | **~: warning sheet opens only after the menu closes; no inline retry** |
| Quit Waddly | terminates | — | — | — |

### 2b. Setup Guide (SwiftUI hosted in the AppKit window)

| Control | Action | Hover | Press | Focus | Disabled | Working | Success | Error |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Option card “Create with ChatGPT” | show the guide | **N: `.buttonStyle(.plain)` has no hover fill** | dims | **~ unverified** | — | — | — | — |
| Option card “Choose a PNG” | open picker | N | dims | ~ | — | — | — | — |
| Copy the prompt and open ChatGPT | copy + open browser | Y | Y | Y | — | — | inline “copied” | inline copy / open failure (#118) |
| Change method | back to options | Y | Y | Y | — | — | — | — |
| Choose a PNG / Change image | picker → read → commit | Y | Y | Y | — | — | inline “Added *file*” | inline failure, previous set kept (#118) |
| Enable Input Monitoring | request + open Settings | Y | Y | Y | — | status polling | guide ends when keys arrive | — |
| Add it another way | toggle manual steps | Y | Y | Y | — | — | manual steps | — |
| Back / Next / Set up later | navigate | Y | Y | Y | **~: Next greyed with no inline reason** | — | step changes | — |
| If it does not work | expand troubleshooting | Y | Y | Y | — | — | restart / reveal / Settings | — |
| Ready: Set up Input Monitoring | jump to the monitoring step | Y | Y | Y | — | — | — | — |
| Preview: Animation / 9 cells | switch the stage | Y | Y | Y | — | — | — | — |
| Preview: Idle/Typing/Enter/Sleep | play that animation | Y | Y | Y | — | — | — | — |
| Preview: Light / Dark | grid background | Y | Y | Y | — | — | — | — |
| Window drop (any step) | import a dropped PNG | — | — | — | — | — | inline “Added” | inline failure, stays on the step (#118) |

The wizard commits a valid sheet immediately — there is **no** review-before-write confirm step
(PR #118 documented this in `docs/setup-wizard-qa.md`, which also holds the state/test map). The
focus ring for `.plain` cards is a source-audited **gap** and needs a manual keyboard pass.

### 2c. Animation Settings editor

Two revisions: `main` (AppKit rows, `PetImageViews.swift`) and #95 / PR #116 (SwiftUI,
`AnimationSettingsView.swift`); the state contract is the same.

| Control | Action | Hover | Focus | Disabled | Working | Success | Error |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Add (per category) | picker → append PNGs | Y (bordered) | Y | — | — | thumbnail appears | alert sheet |
| Remove thumbnail (`×`) | delete a frame | **N: borderless icon, no hover/press affordance** | ~ | **~: allowed only when more than one image; position is the only reason** | — | — | — |
| Move left / right (`‹` / `›`) | reorder within the category | N | ~ | ~: disabled at the ends, position-only reason | — | order updates | — |
| Row drop target | add dropped PNGs | accent border while targeted (Y) | — | non-PNG drag rejected | — | thumbnails appended | alert sheet |
| Window | resize / close | — | — | content minimum covers all four rows (#116) | — | — | — |

### 2d. Share dialog

| Control | Action | Hover | Focus | Working | Success | Error |
| --- | --- | --- | --- | --- | --- | --- |
| Movie preview Play / Pause | toggle local playback | **N** | ~ | poster → player | loops, resets at end | — |
| Copy video | `PetShareClipboard.copyMovie` | **N (#108)** | ~ | — | button title → “Copied” | **N: `NSSound.beep()` only, no message or retry (#109)** |
| Copy sprite | `PetShareClipboard.copyPNG` | **N (#108)** | ~ | — | title → “Copied” | N: beep only |
| X row (logo + “Post on X”) | open a prefilled composer | **cursor only: pointing hand, no fill** | **N: `NSView` + click gesture, not keyboard-focusable** | — | composer opens | **N: no feedback when no handler exists** |
| Window | close | — | — | spinner “Preparing share assets…” | assets shown | inline “Could not create…” (#109 wants a retry) |
| Window close during export | cancels generation | — | — | — | partial temp removed (#115) | — |

`PetShareDialogTests` covers asset prep, close-cancels-generation, the X URL, and label refresh on
language change. Hover, focus, and keyboard remain **manual-unverified**.

### 2e. Sheets and alerts

| Sheet | Trigger | Buttons | Retry |
| --- | --- | --- | --- |
| Import confirm (3×3 preview, `SpriteSheetPreviewAccessory`) | editor / CLI import path | Import / Cancel | re-import from the editor or menu |
| Import error, save error | unreadable PNG / storage limit | OK | re-run the import |
| Login-item error | `SMAppService` throws | OK | re-toggle from the menu |
| Share asset error | export / generation fails | inline label only | **N: no explicit retry (#109)** |

## 3. Lightweight native principles (as applied)

1. **Recognizable controls** — standard `NSButton`, `NSSegmentedControl`, SwiftUI `Button`; no custom
   control chrome. The Share X row (gesture on an `NSView`) is the one non-control control.
2. **Consistent hit area** — option cards are 72 pt, but the thumbnail `×` is 20 × 20 pt and the
   chevrons 26 × 20 pt, below a comfortable ~24 pt target (`PetImageViews.swift`,
   `AnimationSettingsView.swift`).
3. **Pointer / cursor** — only the Share X row sets a pointing hand; everything else, including the
   copy buttons, uses the default arrow. #108 owns consistency.
4. **Visible keyboard focus** — native for menus, buttons, and segments; unverified for SwiftUI
   `.plain` cards and the Share gesture row.
5. **Inline outcomes, no layout shift** — setup uses inline copy/import/error text (#118); Share uses
   a button-title change plus a beep. Hover feedback must never shift layout.
6. **Action hierarchy and motion** — one `borderedProminent` primary per state (Next / Enable /
   Restart / Show on desktop), secondary actions bordered or link. Motion is limited to 180–250 ms
   step cross-fades and the pet reveal, and `MotionPreference.isReduced` disables both.

## 4. QA matrix

The **Result** column is intentionally blank: it is filled in only by a real run. `auto` = a suite
covers the state today; `manual` = needs a GUI / VoiceOver / System Settings session and is
**unverified**.

| Screen | Pointer | Keyboard-only | VoiceOver | Appearance / contrast | Reduce Motion | JA / EN | Failure + retry | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pet panel | drag, right-click, PNG drop, Dock re-front | no keyboard surface (non-key panel) | label + drop tooltip | transparent, follows system | reveal fade suppressed | tooltip localized | invalid/oversized drop → alert sheet | auto: placement, menu; manual: drag feel |
| Setup — Pet | cards, picker, window drop | Tab to cards + Next | grouping and labels | preview backdrop follows appearance (#118) | step cross-fade off | fixed 410 pt column | unreadable PNG → inline, keeps set | auto: `SetupWizardTests`; manual: focus ring |
| Setup — ChatGPT guide | copy+open, Change method, Choose PNG | Tab order | hint on cards | text contrast | — | copy strings | copy/open failure inline (#118) | auto; manual: real browser |
| Setup — permission | Enable, manual steps, Settings hand-off | Tab through the guide | status updates announced | off vs granted distinguishable | polling unaffected | instructions | granted-not-receiving → restart / retry | auto: `PermissionServiceTests`; manual: real TCC |
| Setup — Ready | Back, Show on desktop, Set up monitoring | Tab | checks read out | warning visible | celebrate hop suppressed | checks localized | non-ready never looks like success | auto; manual: spoken order |
| Share | copy, play, X row | **gap: X row not focusable** | roles set; not spoken | checkerboard + card colors (#106 dark mode) | no animation | labels refresh | beep-only, no retry (#109) | auto: `PetShareDialogTests`; manual: hover |
| Preferences menus | all items | arrow / Return native | menu item names | native menu | — | language switch rebuilds | login error sheet | auto: `AppPresenceMenuTests`; manual: disabled reason |
| Animation Settings | add, remove, move, drop | Tab (AppKit buttons focusable) | labels + index names | controlBackground rows | — | titles localized | invalid / save → alert | auto: branch `AnimationSettingsTests` (#116) |

## 5. Walkthroughs (with retry)

**Setup Guide.** 1) Launch to a first-run state → Pet step. 2) Choose a valid 3×3 PNG → preview
updates, inline “Added …”; or copy the prompt and open ChatGPT. 3) *Retry:* choose a non-PNG or
unreadable PNG → inline message, previous pet kept; choose again. If chatgpt.com will not open →
inline open-failure text, Copy again. 4) Next → Input Monitoring; Enable opens System Settings and
the guide parks beside it. 5) *Retry:* after granting, “granted-not-receiving” offers “Restart now”
or “Try again without restarting”. 6) Ready shows both checks filled; without permission it offers
“Set up Input Monitoring” instead of a false success.

**Share.** 1) Right-click the pet (complete image set) → Share Pet. 2) Spinner “Preparing share
assets…” → two cards (5-second video, 3×3 sheet). 3) Play/pause the movie; Copy video / Copy sprite
→ the button title becomes “Copied”. 4) Logo or “Post on X” → composer opens with the draft and
`#ShareMyWaddly`. 5) *Retry:* generation failure shows an inline message but no explicit retry
today (#109); a clipboard failure only beeps today.

**Preferences menus.** 1) Click the menu bar item, or right-click the pet. 2) Change size → the pet
resizes immediately; motion / breathing / language apply immediately and radio/check state stays in
sync. 3) Show in → turning off the last visible entry point is greyed (reason not shown). 4) Launch
at Login → check reflects `SMAppService` status; failure shows a warning sheet after the menu closes.
5) *Retry:* reopen the menu and toggle again.

**Animation Settings.** 1) Right-click pet → Animation Settings… (enabled only after setup). 2) Add
→ pick PNGs; drop a PNG on a row → accent border while targeted, thumbnails append. 3) Reorder with
`‹` / `›`, remove with `×` (disabled at a single image or at the ends). *Retry:* an unsupported file
shows an alert sheet; add again. 4) Close → content cleared; reopen → rebuilt.

## 6. Prioritized gaps by task impact

| Priority | Gap | Impact on the task | Tracked by |
| --- | --- | --- | --- |
| P1 | Share: clipboard failure only beeps, with no inline error or retry | copy is the primary action; the user cannot tell it failed | #109 |
| P1 | Share: no hover/focus feedback on the copy buttons or the X row; X row is not keyboard reachable | wrong target / keyboard users blocked | #108, #109 |
| P2 | Setup: `.plain` option cards have no hover or focus ring | “bring a pet” is the first task; discoverability + keyboard | #94, #110 |
| P2 | Editor: `×` / `‹` / `›` have no hover/press affordance and are 20–26 pt | precise editing is error-prone | #95, #94 |
| P2 | Menus: “Animation Settings…” and the presence guard are disabled with no reason | the user cannot tell why a feature is unavailable | #94 |
| P3 | Login-item failure is a post-menu sheet with no inline retry | recoverable but easy to miss | #94 |
| P3 | Share movie Play / Pause has no hover state | minor affordance | #108 |

No duplicate issues are created; every gap points at an existing tracker.

## 7. Screenshot evidence (existing committed renders only)

The only assets that exist today, verified reachable (HTTP 200) at audit time. They are AppKit
`cacheDisplay` content renders on their branch — **not** screen captures — and were not produced by
this audit.

Setup feedback, PR [#118](https://github.com/nyatinte/Waddly/pull/118):

- Before (EN / light): https://raw.githubusercontent.com/nyatinte/Waddly/agent/issue94-setup-feedback/docs/images/setup-feedback/before-f1918a0-en-light.png
- After (EN / light): https://raw.githubusercontent.com/nyatinte/Waddly/agent/issue94-setup-feedback/docs/images/setup-feedback/after-0c33664-en-light.png
- After (JA / dark): https://raw.githubusercontent.com/nyatinte/Waddly/agent/issue94-setup-feedback/docs/images/setup-feedback/after-0c33664-ja-dark.png

Animation Settings, PR [#116](https://github.com/nyatinte/Waddly/pull/116):

- Before, AppKit (EN / light): https://raw.githubusercontent.com/nyatinte/Waddly/agent/issue95-swiftui-editor/docs/images/animation-settings/before-appkit-f1918a0-en-light.png
- After, SwiftUI (EN / light): https://raw.githubusercontent.com/nyatinte/Waddly/agent/issue95-swiftui-editor/docs/images/animation-settings/after-swiftui-c5f8fcf-en-light.png
- After, SwiftUI (JA / dark): https://raw.githubusercontent.com/nyatinte/Waddly/agent/issue95-swiftui-editor/docs/images/animation-settings/after-swiftui-c5f8fcf-ja-dark.png

Provenance and limits are recorded in each branch's `docs/images/*/README.md`.

## 8. Post-#109 / #110 update spots

- §2d Share table: add hover, focus, working, success, and error/retry rows once #109 lands.
- §2b Setup: record any new first-run step, permission wording, or “try sample now” shortcut (#110).
- §4 matrix: revisit the Share and Setup rows.
- §6: re-rank and drop rows whose trackers are closed.
- §7: replace the links with the merged revisions and re-check reachability.

## 9. Capturing new screenshots (manual, native)

1. `mise run dev:install`, then `mise run dev:reset` for a first-run state; `open "/Applications/Waddly (development).app"`.
2. Set language and appearance; use System Settings → Accessibility for contrast and Reduce Motion.
3. Capture with ⌘⇧4 (window) or ⌘⇧5; keep EN/light, EN/dark, JA/light, JA/dark per changed surface.
4. Store under `docs/images/<surface>/` with a small `README.md` recording revision, language,
   appearance, and that the shot is a real capture; link them from the PR body.
5. A screenshot proves layout only. Keyboard, VoiceOver, and the System Settings hand-off must be
   recorded as manual results, not inferred from a picture.
