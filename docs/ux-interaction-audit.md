# Waddly UX interaction audit and QA matrix

For [#111](https://github.com/nyatinte/Waddly/issues/111). A compact, contributor-maintainable
audit of Waddly's entry points, per-control action/state contracts, and a manual QA matrix. It is
intentionally **not** a design system and it adds no runtime behavior.

## Evidence status — read first

**Monitoring / Share follow-up at `2b2dd32`:** [bounded native QA](live-qa-2b2dd32-monitoring-share.md)
adds actual isolated-app monitoring Close / synthetic Escape observations and controlled live Share
working → failure → Retry → real-export success in EN/light and JA/dark. Ten ScreenCaptureKit captures
retain the distinction between actual-app and injected-effect fixtures, including one helper packaging
crash and an unsuccessful TMPDIR fault attempt. Japanese recovery-message truncation is confirmed in
[#154](https://github.com/nyatinte/Waddly/issues/154). Physical keyboard, spoken VoiceOver, native drops,
real clipboard/browser failures and contrast/Reduce Motion acceptance remain open. #151 is excluded.

**Disabled-menu follow-up:** [native menu reasons and paired renders](images/disabled-menu-help/README.md)
records JA/EN light/dark native popup content, not OS screenshots. Validation now installs localized
help for unavailable character, share and presence commands; macOS 14.4+ also shows a standard
subtitle. The rows below are updated only for that contract. Older-OS tooltip visibility and physical
keyboard/spoken VoiceOver acceptance remain unverified under #111.

**Latest character-import evidence:** [advanced editing/lifecycle follow-up](character-import-follow-up.md)
adds native remove/reorder, minimize/refocus, discard/reopen and custom-frame Apply/relaunch checks,
plus JA/EN native accessibility attribute read-back. Finder/category drag and VoiceOver are still
unverified. [QA at merged main `85b96a8`](live-qa-85b96a8.md) records the earlier
Setup, Share and character-import checks, real window captures, and remaining blockers for #108,
#111 and #124. This was live GUI automation, not human keyboard/VoiceOver acceptance. The refreshed
Share contract below supersedes its old gaps; other source-audit sections retain their stated
historical revisions and must not be mistaken for a fresh audit of all of main.

Baseline claims below are one of two kinds, kept apart throughout:

- **Source-audited** — read directly from the code at the revisions in the table. Describes behavior
  at those revisions, not necessarily current main.
- **Manual-unverified** — needs a real GUI session (VoiceOver, System Settings, live keyboard).
  The baseline did not execute these. Consult the linked live report for the limited checks since
  performed; do not tick an entire manual row from source tests or partial GUI evidence.

| Source | Revision audited | Delta relevant to this audit |
| --- | --- | --- |
| `main` (base of this document) | `f1918a0` | current sources for every surface |
| [#94](https://github.com/nyatinte/Waddly/issues/94) setup feedback, PR [#118](https://github.com/nyatinte/Waddly/pull/118) | `agent/issue94-setup-feedback` @ `86dfce5` | inline setup failure/browser feedback, one accessibility announcement per error transition, preview backdrop follows appearance, `docs/setup-wizard-qa.md` |
| [#95](https://github.com/nyatinte/Waddly/issues/95) editor, PR [#116](https://github.com/nyatinte/Waddly/pull/116) | `agent/issue95-swiftui-editor` @ `a38452f` | Animation Settings → SwiftUI; editor model released on close |
| [#124](https://github.com/nyatinte/Waddly/issues/124) unified character import | `agent/issue124-unified-import` @ `023474d` | shared staged import screen in the Setup Pet step and a new Change Character window; clipboard/DnD/paste; standalone Animation Settings window and menu item retired; committed renders in `docs/images/character-import/` |
| [#96](https://github.com/nyatinte/Waddly/issues/96)/[#99](https://github.com/nyatinte/Waddly/issues/99) share, PR [#115](https://github.com/nyatinte/Waddly/pull/115) | `agent/issue96-99-export-cancellation` @ `4f6398e` | closing Share cancels the in-flight export and removes partial temp assets |

The baseline preceded the merged #109 (Share flow) and #110 (first-run journey) implementations.
Unrefreshed baseline descriptions are historical, not current implementation claims. Share is
source-refreshed at `85b96a8` below; the live report records only observed first-run states.

Screenshot evidence in §7 is historical AppKit `cacheDisplay` rendering, not screen capture.
The linked live report adds separately identified ScreenCaptureKit window captures.

## 1. Entry points and window lifecycle (source-audited)

| Entry point | Trigger | Result | Close / reopen |
| --- | --- | --- | --- |
| Pet panel | left-drag | moves the borderless panel; origin saved and clamped to visible screens | pet stays on the desktop |
| Pet panel | right-click | `makePetContextMenu()` = copy of the status menu with “Share Pet” inserted first | rebuilt per open; `menuWillOpen` refreshes state |
| Pet panel | drop a PNG | imports through the pet-image path (writes only after validation) | — |
| Dock icon | click | setup complete → `bringPetToFront()`; otherwise `showSetupWizard()` | never opens the editor |
| Menu bar item | click | opens the status menu; tooltip reads reaction state (paused / active / permission) | menus rebuild after a language change |
| Status/pet menu | “Setup Guide…” (unfinished) / “Set Up Input Monitoring…” (finished) | resumes unfinished setup, or opens permission/status/recovery directly after completion | unfinished setup keeps its saved step; monitoring settings leaves setup state and saved images unchanged |
| Status/pet menu | “Change Character…” | opens the shared character screen on the committed pet (disabled until setup is complete) | close clears content; reopen reloads the committed pet |
| Setup Guide — Pet step | “Choose a PNG” / “Change image” | opens the shared character screen inside the step | Cancel discards the staged draft, confirming only when it has changes |
| Status/pet menu | “Share Pet” (pet menu only) | opens the Share window | close cancels export and deletes temp assets (#115) |

Setup navigation contract:

- Steps **Pet → Input Monitoring → Ready**. The step indicator shows progress and hides on Ready.
- **Back** exists on Input Monitoring and Ready; Pet has none.
- **Next** is disabled on Pet without an image, and on Input Monitoring until permission is
  genuinely *receiving keys* (not merely granted). It is the window's default action.
- **Set up later** appears only while monitoring is not ready and lands on Ready with an explicit
  warning — it never impersonates success.
- Closing keeps `setupStep`. With a complete pet it sets `setupWizardSeen = true`, so relaunch
  leaves the guide closed; without a pet it clears that flag and launch reopens setup. A saved,
  incomplete step can resume on a Dock click or the Setup Guide menu entry. After completion, the
  menu becomes Set Up Input Monitoring and opens only the permission page. Finishing clears
  the saved step. `isSetupComplete` requires image + seen + cleared step, so a finished guide cannot
  trap the user (`AppDelegate.opensSetupOnLaunch`).
- The wizard is a fixed 820 × 520 pt non-restorable window (`SetupMetrics`), so a stale restored
  frame cannot reflow the layout.
- After completion, monitoring settings hides onboarding progress/Back/Later and offers Close
  regardless of readiness. It has no character-image drop targets or step persistence; character
  replacement stays under Change Character. All four permission/readiness states reuse the existing page.
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
| Show in ▸ Dock / Menu Bar | toggles presence | native subtitle on 14.4+; help tag on 14.0+ (older-OS hover unverified) | check state | — |
| Change Character… | opens the shared character screen | native subtitle on 14.4+; help tag on 14.0+ (older-OS hover unverified) | — | — |
| Setup Guide… / Set Up Input Monitoring… | resumes incomplete setup; after completion opens monitoring settings directly | — | — | — |
| Launch at Login | register/unregister `SMAppService` | — | check reflects real status | **~: warning sheet opens only after the menu closes; no inline retry** |
| Quit Waddly | terminates | — | — | — |

### 2b. Setup Guide (SwiftUI hosted in the AppKit window)

| Control | Action | Hover | Press | Focus | Disabled | Working | Success | Error |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Option card “Create with ChatGPT” | show the guide | **N: `.buttonStyle(.plain)` has no hover fill** | dims | **~ unverified** | — | — | — | — |
| Option card “Choose a PNG” | open picker | N | dims | ~ | — | — | — | — |
| Copy the prompt and open ChatGPT | copy + open browser | Y | Y | Y | — | — | inline “copied” | inline copy / open failure (#118) |
| Change method | back to options | Y | Y | Y | — | — | — | — |
| Choose a PNG / Change image | open the shared character screen (see 2c) | Y | Y | Y | — | — | staged review, then Continue | inline; staged candidate kept |
| Enable Input Monitoring | request + open Settings | Y | Y | Y | — | status polling | guide ends when keys arrive | — |
| Add it another way | toggle manual steps | Y | Y | Y | — | — | manual steps | — |
| Back / Next / Set up later | navigate | Y | Y | Y | **~: Next greyed with no inline reason** | — | step changes | — |
| If it does not work | expand troubleshooting | Y | Y | Y | — | — | restart / reveal / Settings | — |
| Ready: Set up Input Monitoring | jump to the monitoring step | Y | Y | Y | — | — | — | — |
| Preview: Animation / 9 cells | switch the stage | Y | Y | Y | — | — | — | — |
| Preview: Idle/Typing/Enter/Sleep | play that animation | Y | Y | Y | — | — | — | — |
| Preview: Light / Dark | grid background | Y | Y | Y | — | — | — | — |
| Window drop (any step) | stage a dropped PNG while composing, else the direct import | — | — | — | — | — | staged review | inline failure, stays on the step |

The shared import screen stages a sheet before anything is written: the Pet step’s Continue applies the
staged draft through the store, so review-before-write holds in both hosts (#124). The ChatGPT and
sample paths still commit on choice. The cards have no explicit custom focus treatment in source;
their actual native focus rendering still needs a manual keyboard pass. `docs/setup-wizard-qa.md`
holds the setup state/test map.

### 2c. Character import screen (Setup Pet step and Change Character)

One SwiftUI component (`CharacterImportView`) renders in both hosts: inside the Setup Pet step and in
the post-setup **Change Character…** window. Import is staged, never written on acquisition: only
Apply/Continue commits through the store’s serialized queue. `CharacterImportModel` owns the draft,
the validation outcome, and the clipboard availability; the AppKit `SetupPreviewPane` supplies the
real four-pose player and nine-cell grid.

| Control | Action | Hover | Focus | Disabled | Working | Success | Error |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Choose File… | native picker → stage | Y | Y | — | reading row | staged preview, status, metadata | inline reason; staged candidate kept |
| Paste from Clipboard / ⌘V | stage clipboard pixels or a PNG file URL | Y | Y | — | reading row | as above | inline “No image on the clipboard.” or the decode reason |
| Drop zone / window drop | stage one PNG | accent highlight + “Drop to import”, system drag eligibility (Y) | — | — | reading row | as above | inline reason; a multi-file drop → “Choose one 3×3 PNG.” |
| Animation / 9 cells, pose buttons | preview the staged sheet | Y | Y | pose buttons hidden when empty; the Animation / 9 cells switch stays visible | — | real player or nine-cell grid, nearest-neighbor | — |
| Edit frames individually… | reveal the advanced editor over the same draft | Y | Y | shown only with a staged candidate | — | back returns to the parent preview | — |
| Cancel / Back | leave without committing | Y | Y | — | — | returns to the method list; nothing written | discard confirmation only when staged changes exist |
| Apply this character / Continue | commit the draft once | Y | Y | until a complete candidate exists | no progress indicator: the button only greys out while the commit runs | pet and settings update together | inline “Could not save…”; draft kept for retry |

The clipboard is read only on an explicit paste; availability is rechecked on appear and on app
activation without reading pixels. The two hosts differ only in the primary label and the
surrounding navigation.

**Advanced editor** (reused `AnimationSettingsView`, reached from “Edit frames individually…”, no
longer a top-level destination):

| Control | Action | Hover | Focus | Disabled | Working | Success | Error |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Add (per category) | picker → append PNGs to the draft | Y (bordered) | Y | — | — | thumbnail appears | unreadable file skipped |
| Remove thumbnail (`×`) | delete a draft frame | **N: borderless icon, no hover/press background** | ~ | native help explains the last-required-frame guard; JA/EN `AXHelp` read-back verified | — | native deletion observed; parent Apply only | — |
| Move left / right (`‹` / `›`) | reorder within the category | N: no hover background | ~ | native help explains first/last boundaries; JA/EN `AXHelp` read-back verified | — | native reorder observed; survives minimize/refocus | — |
| Row drop target | add dropped PNGs to the draft | accent border while targeted (Y) | — | non-PNG drag rejected | — | thumbnails appended | unreadable file skipped |

Nothing in the advanced editor commits: closing it returns to the parent preview with the draft
intact, and the parent’s Cancel discards it. The former standalone **Animation Settings** window and
its status-menu item are retired (#124). At `ffa65a5`, frame/image action labels include pose and
position, verified through native `AXAttributedDescription`; Orca's plain tree omission is not proof
of a missing label. The [follow-up](character-import-follow-up.md) distinguishes this from spoken
VoiceOver acceptance and from unverified visible hover tooltips.

### 2d. Share dialog

Source-refreshed at `85b96a8`; live observations are restricted to the linked report's configuration.

| Control | Action | Hover | Focus | Working | Success | Error |
| --- | --- | --- | --- | --- | --- | --- |
| Movie preview Play / Pause | toggle local playback | Y: background darkens | unverified live | poster → player | action label switches Play/Pause | — |
| Copy video | `PetShareClipboard.copyMovie` | Y: accent tint | unverified live | — | inline video outcome; stable button title | inline per-asset error; same button retries |
| Copy sprite | `PetShareClipboard.copyPNG` | Y: accent tint | unverified live | — | inline image outcome; stable button title | inline per-asset error; same button retries |
| Post on X (single native button with logo) | open a prefilled composer | Y: accent tint | native button; traversal unverified | disabled until assets are ready | composer opens | inline composer-open failure |
| Retry | retry failed generation | shared button treatment; live unverified | unverified live | returns to generation | assets shown | failure message remains recoverable |
| Window | close | — | — | spinner while generating | assets shown | inline failure plus Retry |
| Window close during export | cancels generation | — | — | — | partial temp removed | — |

`PetShareDialogTests` and `PetShareFlowTests` cover state/effect contracts. The live session observed
hover, copy outcomes and playback. The later [bounded QA](live-qa-2b2dd32-monitoring-share.md) adds
live injected-effect working/disabled/failure/Retry transitions in EN/light and JA/dark, not actual OS
clipboard/browser faults. Japanese visual recovery text truncation is tracked in #154. Tab traversal,
held press, spoken VoiceOver, physical pointer, contrast and Reduce Motion remain unverified.

### 2e. Sheets and alerts

| Sheet | Trigger | Buttons | Retry |
| --- | --- | --- | --- |
| Import confirm (3×3 preview, `SpriteSheetPreviewAccessory`) | pet-panel PNG drop (`AppDelegate.importPetImage`) | Import / Cancel | drop another PNG |
| Import error, save error | unreadable PNG / storage limit | OK | re-run the import |
| Login-item error | `SMAppService` throws | OK | re-toggle from the menu |
| Share asset error | export / generation fails | inline label plus Retry (`85b96a8`) | Retry starts generation again; live failure walkthrough still unverified |

## 3. Lightweight native principles (as applied)

1. **Recognizable controls** — standard `NSButton`, `NSSegmentedControl`, SwiftUI `Button`; no custom
   control chrome. Share's former gesture row is now a native Post button (`85b96a8`).
2. **Consistent hit area** — option cards are 72 pt, but the thumbnail `×` is 20 × 20 pt and the
   chevrons 26 × 20 pt, below a comfortable ~24 pt target (`PetImageViews.swift`,
   `AnimationSettingsView.swift`).
3. **Pointer / cursor** — Share now uses native buttons with background hover feedback instead of
   the historical gesture row's pointing-hand-only affordance. #108 owns consistency and remaining
   live acceptance.
4. **Visible keyboard focus** — native for menus, buttons, and segments; unverified for SwiftUI
   `.plain` cards; live traversal is still unverified for Share's native buttons.
5. **Inline outcomes, no layout shift** — setup uses inline copy/import/error text (#118); Share now
   uses per-asset inline outcomes with stable button labels. Hover feedback must never shift layout.
6. **Action hierarchy and motion** — one `borderedProminent` primary per state (Next / Enable /
   Restart / Show on desktop), secondary actions bordered or link. Motion is limited to 180–250 ms
   step cross-fades and the pet reveal, and `MotionPreference.isReduced` disables both.

## 4. QA matrix

`auto` means a suite covers the stated behavior; `manual` means a GUI / VoiceOver / System Settings
session is still **unverified**. Record manual results with OS, revision, and observed outcome after
execution; an automated state test does not verify every interaction in its row.

| Screen | Pointer | Keyboard-only | VoiceOver | Appearance / contrast | Reduce Motion | JA / EN | Failure + retry | Coverage |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pet panel | drag, right-click, PNG drop, Dock re-front | no keyboard surface (non-key panel) | label + drop tooltip | transparent, follows system | reveal fade suppressed | tooltip localized | invalid/oversized drop → alert sheet | auto: placement, menu; manual: drag feel |
| Setup — Pet | cards, picker, window drop, shared staged screen | Tab to cards + Next | grouping and labels | preview backdrop follows appearance (#118) | step cross-fade off | fixed 820 × 520 window; shared screen fits | unreadable PNG → inline, keeps set; failed save → inline retry | auto: `SetupWizardTests`, `SetupWizardCharacterImportTests`; manual: focus ring |
| Setup — ChatGPT guide | copy+open, Change method, Choose PNG | Tab order | hint on cards | text contrast | — | copy strings | copy/open failure inline (#118) | auto; manual: real browser |
| Setup — permission | Enable, manual steps, Settings hand-off | Tab through the guide | status updates announced | off vs granted distinguishable | polling unaffected | instructions | granted-not-receiving → restart / retry | auto: `PermissionServiceTests`; manual: real TCC |
| Monitoring settings (completed setup) | native menu entry and Close observed; Finder drop unverified | synthetic Escape followed by window disappearance; physical keys/focus pending | attributed Close/status read-back; not spoken | EN/dark native capture | live setting unverified | EN executed; other locale/state combinations not established here | no saved image/setup changes; live TCC recovery pending | auto: `InputMonitoringSettingsTests`; live: [bounded results](live-qa-2b2dd32-monitoring-share.md) |
| Setup — Ready | Back, Show on desktop, Set up monitoring | Tab | checks read out | warning visible | celebrate hop suppressed | checks localized | non-ready never looks like success | auto; manual: spoken order |
| Share | prior synthetic hover/copy/play plus live fixture AX Retry/error actions | native Post button; physical shortcuts and traversal unverified | full error text in AX; not spoken | EN/light and JA/dark native fixture captures; contrast unverified | no added hover animation; live setting unverified | both executed combinations; JA errors visually truncate (#154) | injected generation failure → Retry → real export observed; actual OS faults pending | auto: `PetShareDialogTests`, `PetShareFlowTests`; live: [earlier](live-qa-85b96a8.md), [bounded follow-up](live-qa-2b2dd32-monitoring-share.md) |
| Preferences menus | all items | arrow / Return native | menu item names | native menu | — | language switch rebuilds | login error sheet | auto: `AppPresenceMenuTests`, `MenuDisabledHelpTests`; manual: older-OS help, keyboard/VoiceOver |
| Character import (Change Character) | Choose/Paste observed earlier; advanced delete/reorder, minimize/refocus and discard/reopen observed; native drop still unverified | ⌘V observed live; Tab traversal still unverified | labels set; not spoken | light/dark pane, semantic colors; committed renders exist | no animation | EN/JA strings + renders | inline per-reason error + retry; save failure keeps the draft | auto: `CharacterImportModelTests`, `SetupWizardCharacterImportTests`; manual: VoiceOver/keyboard |

## 5. Walkthroughs (with retry)

**Setup Guide.** 1) Launch to a first-run state → Pet step. 2) Choose a valid 3×3 PNG → preview
updates, inline “Added …”; or copy the prompt and open ChatGPT. 3) *Retry:* choose a corrupt or
unreadable file with a `.png` extension → inline message, previous pet kept; choose again. The picker
filters non-PNG files and the drop target rejects their extensions without an import error. If chatgpt.com will not open →
inline open-failure text, Copy again. 4) Next → Input Monitoring; Enable opens System Settings and
the guide parks beside it. 5) *Retry:* after granting, “granted-not-receiving” offers “Restart now”
or “Try again without restarting”. 6) Ready shows both checks filled; without permission it offers
“Set up Input Monitoring” instead of a false success.

**Share.** 1) Right-click the pet (complete image set) → Share Pet. 2) Spinner “Preparing share
assets…” → two cards (5-second video, 3×3 sheet). 3) Play/pause the movie; Copy video / Copy sprite
→ an inline outcome appears next to each asset, with stable button labels. 4) The single native
“Post on X” button → composer opens with the draft and `#ShareMyWaddly` (not exercised live in this
session). 5) *Retry:* generation failure offers Retry; clipboard failure is inline and the same copy
button retries. The [bounded native fixture walkthrough](live-qa-2b2dd32-monitoring-share.md) observed
injected generation failure → Retry → real export, and injected copy/browser failure views. Actual
system faults and physical/spoken acceptance remain pending; JA recovery text truncation is #154.

**Preferences menus.** 1) Click the menu bar item, or right-click the pet. 2) Change size → the pet
resizes immediately; motion / breathing / language apply immediately and radio/check state stays in
sync. 3) Show in → turning off the last visible entry point is greyed, with native help and a subtitle on macOS 14.4+. 4) Launch
at Login → check reflects `SMAppService` status; failure shows a warning sheet after the menu closes.
5) *Retry:* reopen the menu and toggle again.

**Character import.** 1) First run: Pet step → “Choose a PNG”; after setup: right-click pet →
Change Character… (enabled only after setup), which opens the same screen on the committed pet.
2) Choose a file, paste, or drop one PNG → the draft is staged and previewed; nothing is written.
*Retry:* a corrupt or unreadable file with a `.png` extension shows an inline reason and keeps the
staged candidate; a paste with an empty clipboard says so inline; a multi-file sheet drop is refused.
3) Toggle nine cells or a pose to inspect the staged sheet; “Edit frames individually…” adds/removes/
reorders frames over the same draft. 4) Apply this character (*or the Pet step’s Continue*) commits
once through the store; a failed save shows an inline retry and keeps the draft. 5) Cancel with staged
changes asks before discarding; an untouched screen leaves immediately. 6) Close → content cleared;
reopen → the committed pet is loaded again.

## 6. Prioritized gaps by task impact

| Priority | Gap | Impact on the task | Tracked by |
| --- | --- | --- | --- |
| P1 | Share: keyboard focus/traversal not established by the live session | native Post and hover implementation exist, but keyboard acceptance remains unverified | #108, #111 |
| P2 | Share: Japanese recovery instructions visually truncate at the default footprint | a copy/browser error hides the end of its recovery instructions; full AX text does not solve visual readability | #154 |
| P2 | Share: real clipboard/browser failure and recovery still pending | controlled live fixtures establish UI transitions, not actual OS faults or paste compatibility | #109, #111 |
| P2 | Setup: `.plain` option cards have no explicit hover/focus styling; native focus is unverified | “bring a pet” is the first task; discoverability + keyboard | #94, #110 |
| P2 | Advanced editor: `×` / `‹` / `›` have no hover/press affordance and are 20–26 pt | precise editing is error-prone | #95, #94 |
| P2 | Character import: the Paste control is subdued but not disabled when the clipboard is empty, and its tooltip is the only visual difference | a user may click a control that cannot succeed | #124 |
| P2 | Menus: reasons implemented; 14.0–14.3 hover visibility and physical keyboard/VoiceOver remain unverified | native popup renders and validation do not establish those acceptance cases | #111 |
| P3 | Login-item failure is a post-menu sheet with no inline retry | recoverable but easy to miss | #94 |
| P3 | Share hover checked only with synthetic pointer input in dark appearance | light/contrast and physical-device acceptance remain outstanding | #108 |

The new confirmed Share truncation finding is scoped to #154; residual acceptance remains in #111.
Do not create another tracker for already-owned keyboard/VoiceOver or system-failure acceptance.

## 7. Historical screenshot evidence (committed renders)

Assets verified reachable (HTTP 200) at the original audit time; newer live captures are linked above.
These are AppKit `cacheDisplay` content renders on their branch — **not** screen captures — and were
not produced by this audit.

Setup feedback, PR [#118](https://github.com/nyatinte/Waddly/pull/118):

- Before (EN / light): https://raw.githubusercontent.com/nyatinte/Waddly/bebbf10c27fdc9e49c35cbb2a80e6338aadb62b3/docs/images/setup-feedback/before-f1918a0-en-light.png
- After (EN / light): https://raw.githubusercontent.com/nyatinte/Waddly/bebbf10c27fdc9e49c35cbb2a80e6338aadb62b3/docs/images/setup-feedback/after-0c33664-en-light.png
- After (JA / dark): https://raw.githubusercontent.com/nyatinte/Waddly/bebbf10c27fdc9e49c35cbb2a80e6338aadb62b3/docs/images/setup-feedback/after-0c33664-ja-dark.png

Animation Settings, PR [#116](https://github.com/nyatinte/Waddly/pull/116):

- Before, AppKit (EN / light): https://raw.githubusercontent.com/nyatinte/Waddly/a38452fcee8dd7d54f2d11d3d8ea793b17ed1c52/docs/images/animation-settings/before-appkit-f1918a0-en-light.png
- After, SwiftUI (EN / light): https://raw.githubusercontent.com/nyatinte/Waddly/a38452fcee8dd7d54f2d11d3d8ea793b17ed1c52/docs/images/animation-settings/after-swiftui-c5f8fcf-en-light.png
- After, SwiftUI (JA / dark): https://raw.githubusercontent.com/nyatinte/Waddly/a38452fcee8dd7d54f2d11d3d8ea793b17ed1c52/docs/images/animation-settings/after-swiftui-c5f8fcf-ja-dark.png

Character import, #124 (committed in-repo at this revision):

- Renders and provenance: `docs/images/character-import/` (40 files) — empty, drag-eligible,
  clipboard ready/empty, valid + nine cells, invalid, advanced editor, and the Setup Pet step host;
  EN/JA × light/dark. What they do not claim:
  [`docs/images/character-import/README.md`](images/character-import/README.md).
- These are content renders, not screen captures, and were not produced by a GUI session.

Provenance and limits are recorded in each revision's `docs/images/*/README.md`. These immutable
commit URLs survive branch deletion; update the source-audit rows separately when behavior changes.

## 8. Remaining refresh and acceptance work

- §2d/§4/§6 retain the Share contract refreshed at `85b96a8` plus [bounded QA at `2b2dd32`](live-qa-2b2dd32-monitoring-share.md).
  Fix #154 and complete physical keyboard, spoken accessibility and actual system-failure checks;
  controlled effects and screen captures do not establish those acceptance cases.
- §2b Setup: refresh the historical source inventory against merged #110, including the sample path
  and functional monitoring readiness. The session report verifies only selected live states.
- §4 matrix: complete full Setup, preferences and advanced-editor walkthroughs; partial passes do not
  establish entire screen/input/appearance rows.
- §6: re-rank and drop source gaps once actually resolved; retain unverified acceptance work.
- §7: preserve render provenance; add live evidence separately rather than relabeling old fixtures.
- §2c/§4 after #124: re-run the manual keyboard / VoiceOver / contrast passes for the shared screen and
  the Change Character window, and re-check the clipboard-empty affordance decision above.

## 9. Capturing new screenshots (manual, native)

1. `mise run dev:install`; `open "/Applications/Waddly (development).app"`. For first-run captures, use disposable development preferences. `mise run dev:reset` clears development-app state: run it only if you intentionally want to discard that state, never on a user's production setup.
2. Set language and appearance; use System Settings → Accessibility for contrast and Reduce Motion.
3. Capture with ⌘⇧4 (window) or ⌘⇧5; keep EN/light, EN/dark, JA/light, JA/dark per changed surface.
4. Store under `docs/images/<surface>/` with a small `README.md` recording revision, language,
   appearance, and that the shot is a real capture; link them from the PR body.
5. A screenshot proves layout only. Keyboard, VoiceOver, and the System Settings hand-off must be
   recorded as manual results, not inferred from a picture.
