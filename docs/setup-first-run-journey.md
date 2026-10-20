# First-run journey, states, and QA tasks

Time-to-first-pet is the goal: a new user should see the pet react to typing without learning
settings, and should never be shown a success state that the machine has not actually reached. This
page is the audited map of the setup journey, the saved state that survives relaunch, and the
scripted tasks that still need a real GUI session. It reflects the code at
`agent/issue110-journey-mainline` and is written from the actual `SetupWizardController`,
`PermissionService`, and `AppSettings`.

Scope: journey, task completion, and recovery. Visual polish is #94; the SwiftUI architecture
migration is #95; the animation/permission lifecycle is #63/#98. Nothing here adds a mandatory step.

## Journey map

| Journey | Entry | What the user sees | Actions | Exit / saved state |
| --- | --- | --- | --- | --- |
| Fresh install | No pet frames and `setupWizardSeen == false` | Pet step. The bundled sample animates in the preview, labelled “Sample”, with a one-line body. | Create with ChatGPT / Choose a PNG / **Try the sample pet first** / drop a PNG | Import or sample writes frames; `setupStep` still `nil` until a step change |
| Finished setup / existing-user upgrade | `setupWizardSeen == true`, a complete pet, and `setupStep == nil` | No wizard on launch; the pet is on the desktop. `Set Up Input Monitoring…` opens only permission/status/recovery, without character setup, progress indicator, Back, or Later. | Permission/recovery actions, Close; Change Character remains a separate menu action | Opening/closing monitoring settings leaves the saved character and setup state unchanged |
| Denied permission | On the Keyboard reactions step | “not allowed”, the privacy note, and **Enable Input Monitoring** | Enable → guide opens System Settings; or **Add it another way**; or **Set up later** | Granted lands in `setupStep = 1`; Later records `setupStep = 2`, permission TCC untouched |
| Interrupted setup | The window closed before the finish action | With a complete pet, nothing reopens by itself; the Dock click or **Setup Guide…** resumes at the saved step. With no pet yet, the next launch reopens the guide. | Continue, or reopen from the Dock/menu | Closing a complete pet sets `setupWizardSeen = true`; closing without a pet clears it; `setupStep` is kept either way |
| Returning user | Completed once, then reopened | Finish page with the pet check and the monitoring check as they truly are | **Show on desktop**, or **Set up Input Monitoring** if the check is empty | No onboarding restart; a completed guide never traps the user in setup |

## State transitions and saved invariants

The app persists four things that a relaunch reads: `petImageFiles` (plus the frame files on disk),
`setupWizardSeen`, `setupStep`, and the macOS Input Monitoring grant. The app never stores key codes;
`isReceivingKeys` only reports whether the event tap is live, and the observed-reaction signal is a
single in-memory boolean that is never persisted or logged.

| State | Shown on the Keyboard reactions step | Next enabled | Saved invariant |
| --- | --- | --- | --- |
| No pet frames | n/a — the Pet step blocks | No | `petImageFiles` empty, `setupStep` unchanged |
| Pet ready | Wizard shows the pet; sample is labelled as the sample | Pet → Next | Frames on disk + manifest |
| Permission not granted | “not allowed”, guide or manual steps | No | TCC not granted; `setupStep` = 1 |
| Granted, tap unavailable | “restart required” + Restart / retry | No | TCC granted; event tap not running |
| Tap live, no key yet | “waiting for a key press”, pet awake | No | TCC granted; tap running; no delivered key |
| Key observed | “allowed”, pet has reacted | Yes | TCC granted; tap running; a delivered key |
| Finished, reactions confirmed | Completion page, both checks filled | Yes → Show on desktop | `setupWizardSeen = true`, `setupStep = nil` |
| Finished, reactions unconfirmed | Completion page, “waiting for a key press” + Confirm typing | Yes (non-destructive) | `setupWizardSeen = true`, `setupStep = nil`, no delivered key |
| Finished, permission missing | Completion page, monitoring check empty + warning | Yes (non-destructive) | `setupWizardSeen = true`, `setupStep = nil`, TCC missing |

Transitions:

```
launch ─ no pet or unseen ─► Pet ──(import / Try the sample)──► Pet(registered)
  │                                │
  │                                └─(Next)─► Keyboard reactions
  │                                              │
  │                     not granted ─────────────┤
  │                          │ enable/guide      │ granted, tap unavailable ──► restart required
  │                          ▼                   │        │
  │                     System Settings          │        └─(retry / relaunch)─► tap live
  │                          │ grant             │ tap live, no key yet ──► waiting for a key
  │                          └───────────────────┘        │
  │                                                       └─(a real key reaches Waddly)─► confirmed
  │                                                                 │
  │                                                                 └─(Next)─► Ready
  └─(Later on Keyboard reactions)─────────────────────────────────────────► Ready (incomplete warning)

Close any step ── keeps setupStep ──► the Dock click or the menu's Setup Guide resumes that step
Complete pet + close ── setupWizardSeen = true ──► relaunch does NOT reopen the guide; unfinished steps resume from Dock/menu
Finished setup + menu ──► Input Monitoring settings only; Close preserves setupStep = nil
No complete pet + close ── setupWizardSeen = false ──► relaunch reopens the guide
Ready + Show on desktop ── clears setupStep ──► never reopens onboarding
```

Invariants the flow keeps:

- **No false ready.** `Next` stays disabled until a real key has reached Waddly on a tap that is
  still running (`isMonitoringReady`: granted, tap live, key observed). A missing permission, an
  unavailable tap, and a live-but-silent tap are each shown as their own unconfirmed state; pausing
  stops the tap, so a confirmation from before the pause does not survive it.
- **Confirmation is ephemeral and private.** The observed signal is a single boolean set inside the
  event tap; it stores no key code, text, or time, and a new tap clears it. Nothing is logged or sent.
- **Later is explicit and non-destructive.** `deferMonitoring` only sets the phase to deferred and the
  step to Ready; it does not change TCC and does not clear the pet. It never marks reactions confirmed.
- **Resume never loses work.** Step changes record `setupStep`; only the finish action clears it.
  Closing the window keeps the frames and the step.
- **The sample cannot replace a pet the user asked for.** “Try the sample pet first” is offered only
  while no complete pet exists *and* no file import is between the user's choice and its commit.
  While an import is pending the sample is refused, so it cannot queue a commit behind the user's
  file; if the sample is already committing, the user's file is enqueued after it and lands last. The
  refusal is re-checked inside the app's serialized image commit, so a reopened guide cannot sample
  over an import that a previous window already wrote. Nothing is written until the user clicks it,
  and it never changes the step or the saved progress.
- **Errors are in place.** An unreadable sheet or a failed copy/open is reported inline on the current
  step and leaves the previous pet untouched (immediate-import contract from #94).

## Scripted first-run tasks (manual QA — not yet run)

Each task needs the development app's own data directory (`mise run dev:install`, then
`mise run dev:reset` to clear it) and a real Input Monitoring decision. `mise run dev:reset` only
touches the development app's own images and preferences (its separate bundle id); never run it
against a release or a user's installed app, where it would discard their pet and settings.
Completion criteria are observable; a task is not a pass until the observable state is seen on
screen. Run each in English and Japanese, in light and dark.

1. **Fresh pet in one click.** Launch with no pet. Expected: the sample animates in the preview and
   “Try the sample pet first” is visible. Click it. Expected: the pet fills the preview, the page says
   the sample is in use, `Next` becomes enabled, and the step did not change. Failure: the button is
   missing, the window clips, or progress jumps.
2. **Own pet import.** From task 1, use **Change image** (or **Choose a PNG**) to open the shared
   character screen. Choose, paste, or drop a valid 3×3 PNG. Expected: the sheet is staged and
   previewed with its filename, dimensions, and cell size; nothing is written yet. Press **Continue**.
   Expected: the sheet is applied once, the sample message disappears, and the preview shows the
   imported frames. Failure: setup writes before Continue, the previous pet is lost, or Continue
   advances without a successful apply.
3. **Permission honest before and after the tap.** Continue to Keyboard reactions with permission not
   granted. Expected: “not allowed” and the privacy note. Grant in System Settings and return.
   Expected: while the tap is unavailable the page says “restart required” and `Next` is disabled;
   after Restart (or the retry that starts the tap) the page says “waiting for a key press” and
   `Next` stays disabled. Press a key. Expected: the pet reacts and the page switches to “allowed”
   with `Next` enabled. Failure: “ready” appears before any key has reached Waddly, or a live tap
   with no key press is reported as success.
4. **Explicit Later, then resume.** On Keyboard reactions choose **Set up later**. Expected: the
   completion page shows the pet check filled and the monitoring check incomplete with the warning,
   and no false success. Close the window and reopen from the Dock. Expected: it resumes on the
   completion page, not the first step, with the warning still shown.
5. **Interrupt and reopen mid-step.** With a complete pet, close the window on the Keyboard
   reactions step. Expected: relaunching the app does **not** reopen the guide by itself; a Dock
   click or **Setup Guide…** reopens it on the saved step with the same status, the pet unchanged,
   and the file manifest unchanged. Then repeat the close once more with no pet imported: a relaunch
   does reopen the guide at the Pet step. Failure: a relaunch with a complete pet restarts setup, or
   the pet disappears.

Also confirm on the machine (not covered by unit tests): VoiceOver reads each status once and speaks
an inline failure once; keyboard-only Tab/Space/Return reach every action; Reduce Motion removes the
step cross-fade; larger text and increased contrast keep the footer and buttons visible; the System
Settings hand-off parks without covering the list.

## Renders (before / after)

These are native AppKit content-view renders of the hosted `SetupWizardScreen`, not screen captures,
and they do not prove keyboard, VoiceOver, or manual interaction. Each was built from `git archive`
of the named revision with the repository example sheet as the sample and isolated temporary
preferences. Full provenance, including language and appearance per file, is in
[docs/images/setup-journey/README.md](images/setup-journey/README.md).

Before (`e7a026d`, `origin/main` / v1.3.0) — Pet step, no pet:

| English / light | English / dark | Japanese / light | Japanese / dark |
| --- | --- | --- | --- |
| ![before en light](images/setup-journey/before-e7a026d-en-light.png) | ![before en dark](images/setup-journey/before-e7a026d-en-dark.png) | ![before ja light](images/setup-journey/before-e7a026d-ja-light.png) | ![before ja dark](images/setup-journey/before-e7a026d-ja-dark.png) |

After (`5bf0baf`, sample shortcut) — Pet step, no pet:

| English / light | English / dark | Japanese / light | Japanese / dark |
| --- | --- | --- | --- |
| ![after en light](images/setup-journey/after-5bf0baf-en-light.png) | ![after en dark](images/setup-journey/after-5bf0baf-en-dark.png) | ![after ja light](images/setup-journey/after-5bf0baf-ja-light.png) | ![after ja dark](images/setup-journey/after-5bf0baf-ja-dark.png) |

After (`5bf0baf`) — sample chosen, “sample is active” message:

| English / light | English / dark | Japanese / light | Japanese / dark |
| --- | --- | --- | --- |
| ![sample en light](images/setup-journey/after-sample-5bf0baf-en-light.png) | ![sample en dark](images/setup-journey/after-sample-5bf0baf-en-dark.png) | ![sample ja light](images/setup-journey/after-sample-5bf0baf-ja-light.png) | ![sample ja dark](images/setup-journey/after-sample-5bf0baf-ja-dark.png) |

Keyboard reactions (`d5f1120`) — live tap, no key yet (“waiting for a key press”, Next disabled):

| English / light | English / dark | Japanese / light | Japanese / dark |
| --- | --- | --- | --- |
| ![awaiting en light](images/setup-journey/monitoring-awaiting-d5f1120-en-light.png) | ![awaiting en dark](images/setup-journey/monitoring-awaiting-d5f1120-en-dark.png) | ![awaiting ja light](images/setup-journey/monitoring-awaiting-d5f1120-ja-light.png) | ![awaiting ja dark](images/setup-journey/monitoring-awaiting-d5f1120-ja-dark.png) |

Keyboard reactions (`5bf0baf`) — a key delivered (confirmed, Next enabled):

| English / light | English / dark | Japanese / light | Japanese / dark |
| --- | --- | --- | --- |
| ![confirmed en light](images/setup-journey/monitoring-confirmed-5bf0baf-en-light.png) | ![confirmed en dark](images/setup-journey/monitoring-confirmed-5bf0baf-en-dark.png) | ![confirmed ja light](images/setup-journey/monitoring-confirmed-5bf0baf-ja-light.png) | ![confirmed ja dark](images/setup-journey/monitoring-confirmed-5bf0baf-ja-dark.png) |

These renders were made from fixture state, not a live typing session: the awaiting/confirmed states
were set by pointing the fixture's `hasObservedReaction` at false/true. Inspect them for text and
footer clipping at the default font; the Japanese lines are the worst case. Larger text, contrast,
VoiceOver, real keyboard confirmation, and Reduce Motion still need a manual pass.

## Automated verification

`mise run test` covers the state machine; see the tables in
[setup-wizard-qa.md](setup-wizard-qa.md). The journey additions live in the `SetupWizardJourneyTests`
suite: `tryingTheSampleCommitsTheBundledSampleInPlace`, `tryingTheSampleNeverReplacesAnExistingPet`,
`importingARealSheetClearsTheSampleChoice`, `rapidSampleRequestsCommitOnce`,
`interruptedPermissionFlowResumesToRestartRequired`,
`deferringSavesTheReadyStepSoARelaunchCanResume`, `aLiveTapStaysUnconfirmedUntilAKeyArrives`,
`deferringFromALiveTapKeepsTheCheckWaiting`, and `aReturningUserKeepsAConfirmedReaction`. The sample
guard tests live in the `SetupWizardSampleGuardTests` suite:
`sampleIsIgnoredWhileAUserImportIsStillCommitting`,
`aReopenedWizardCannotSampleOverAUserImportStillCommitting`, and
`aFailedImportReleasesTheSampleShortcut`. The readiness rules themselves are covered by
`PermissionServiceTests` (`aLiveTapWithoutADeliveredKeyIsAwaitingReaction`,
`readinessSeparatesMissingPermissionFromAnUnavailableTap`, `deferringDoesNotConfirmReactions`).
