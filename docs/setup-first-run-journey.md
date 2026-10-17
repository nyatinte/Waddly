# First-run journey, states, and QA tasks

Time-to-first-pet is the goal: a new user should see the pet react to typing without learning
settings, and should never be shown a success state that the machine has not actually reached. This
page is the audited map of the setup journey, the saved state that survives relaunch, and the
scripted tasks that still need a real GUI session. It reflects the code at `agent/issue110-first-run`
and is written from the actual `SetupWizardController`, `PermissionService`, and `AppSettings`.

Scope: journey, task completion, and recovery. Visual polish is #94; the SwiftUI architecture
migration is #95; the animation/permission lifecycle is #63/#98. Nothing here adds a mandatory step.

## Journey map

| Journey | Entry | What the user sees | Actions | Exit / saved state |
| --- | --- | --- | --- | --- |
| Fresh install | No pet frames and `setupWizardSeen == false` | Pet step. The bundled sample animates in the preview, labelled “Sample”, with a one-line body. | Create with ChatGPT / Choose a PNG / **Try the sample pet first** / drop a PNG | Import or sample writes frames; `setupStep` still `nil` until a step change |
| Existing-user upgrade | `setupWizardSeen == true` and a complete pet | No wizard on launch; the pet is on the desktop. `Setup Guide…` opens it deliberately. | Menu actions | Setup does not reopen; `setupStep` stays `nil` |
| Denied permission | On the Keyboard reactions step | “not allowed”, the privacy note, and **Enable Input Monitoring** | Enable → guide opens System Settings; or **Add it another way**; or **Set up later** | Granted lands in `setupStep = 1`; Later records `setupStep = 2`, permission TCC untouched |
| Interrupted setup | The window closed before the finish action | Reopening resumes at the saved step (`setupStep`) | Continue, or reopen from the Dock | `setupStep` is kept while the pet is complete; closing does not clear it |
| Returning user | Completed once, then reopened | Finish page with the pet check and the monitoring check as they truly are | **Show on desktop**, or **Set up Input Monitoring** if the check is empty | No onboarding restart; a completed guide never traps the user in setup |

## State transitions and saved invariants

The app persists four things that a relaunch reads: `petImageFiles` (plus the frame files on disk),
`setupWizardSeen`, `setupStep`, and the macOS Input Monitoring grant. The app never stores key codes;
`isReceivingKeys` only reports whether the event tap is live.

| State | Shown on the Keyboard reactions step | Next enabled | Saved invariant |
| --- | --- | --- | --- |
| No pet frames | n/a — the Pet step blocks | No | `petImageFiles` empty, `setupStep` unchanged |
| Pet ready | Wizard shows the pet; sample is labelled as the sample | Pet → Next | Frames on disk + manifest |
| Permission not granted | “not allowed”, guide or manual steps | No | TCC not granted; `setupStep` = 1 |
| Granted, tap silent | “restart required” + Restart / retry | No | TCC granted; tap not running |
| Granted, keys arriving | “allowed”, try-typing | Yes | TCC granted; tap running |
| Finished, permission ready | Completion page, both checks filled | Yes → Show on desktop | `setupWizardSeen = true`, `setupStep = nil` |
| Finished, permission missing | Completion page, monitoring check empty + warning | Yes (non-destructive) | `setupWizardSeen = true`, `setupStep = nil`, TCC missing |

Transitions:

```
launch ─ no pet or unseen ─► Pet ──(import / Try the sample)──► Pet(registered)
  │                                │
  │                                └─(Next)─► Keyboard reactions
  │                                              │
  │                     not granted ─────────────┤
  │                          │ enable/guide      │ granted, tap silent ──► restart required
  │                          ▼                   │        │
  │                     System Settings          │        └─(retry / relaunch / keys arrive)─► ready
  │                          │ grant             │ granted, keys arriving ──► ready
  │                          └───────────────────┘        │
  │                                                       └─(Next)─► Ready
  └─(Later on Keyboard reactions)────────────────────────────────────► Ready (warning shown)

Close any step  ── keeps setupStep ──► Dock reopen / relaunch resumes that step
Reach Ready + Show on desktop ── clears setupStep, sets setupWizardSeen ──► never reopens onboarding
```

Invariants enforced by construction:

- **No false ready.** `Next` stays disabled until `isMonitoringReady` (granted *and* keys arriving).
  A granted-but-silent tap is “restart required”, not success.
- **Later is explicit and non-destructive.** `deferMonitoring` only sets the phase to deferred and the
  step to Ready; it does not change TCC and does not clear the pet.
- **Resume never loses work.** Step changes record `setupStep`; only the finish action clears it.
  Closing the window keeps the frames and the step.
- **The sample cannot clobber a pet.** “Try the sample pet first” is offered only when no complete
  pet exists, and it commits through the same path as an import. Nothing is written until the user
  clicks it; it never changes the step or the saved progress.
- **Errors are in place.** An unreadable sheet or a failed copy/open is reported inline on the current
  step and leaves the previous pet untouched (immediate-import contract from #94).

## Scripted first-run tasks (manual QA — not yet run)

Each task needs a fresh data directory (`mise run dev:reset` with `mise run dev:install`) and a real
Input Monitoring decision. Completion criteria are observable; a task is not a pass until the
observable state is seen on screen. Run each in English and Japanese, in light and dark.

1. **Fresh pet in one click.** Launch with no pet. Expected: the sample animates in the preview and
   “Try the sample pet first” is visible. Click it. Expected: the pet fills the preview, the page says
   the sample is in use, `Next` becomes enabled, and the step did not change. Failure: the button is
   missing, the window clips, or progress jumps.
2. **Own pet import.** From task 1, use **Change image** and pick a valid 3×3 PNG. Expected: the image
   registers immediately, the sample message disappears, and the preview shows the imported frames.
   Failure: a confirm dialog appears, or the previous pet is lost.
3. **Permission honest before and after the tap.** Continue to Keyboard reactions with permission not
   granted. Expected: “not allowed” and the privacy note. Grant in System Settings and return.
   Expected: while the tap is silent the page says “restart required” and `Next` is disabled; after
   Restart (or the retry that starts the tap) it says “allowed” and `Next` enables. Failure: “ready”
   appears while typing does not move the pet.
4. **Explicit Later, then resume.** On Keyboard reactions choose **Set up later**. Expected: the
   completion page shows the pet check filled and the monitoring check empty with the warning, no
   false success. Close the window and reopen from the Dock. Expected: it resumes on the completion
   page, not the first step, with the warning still shown.
5. **Interrupt and reopen mid-step.** Close the window on the Keyboard reactions step, relaunch.
   Expected: the guide reopens on that step with the same status, the pet is unchanged, and the file
   manifest on disk is unchanged. Failure: setup restarts at the Pet step, or the pet disappears.

Also confirm on the machine (not covered by unit tests): VoiceOver reads each status once and speaks
an inline failure once; keyboard-only Tab/Space/Return reach every action; Reduce Motion removes the
step cross-fade; larger text and increased contrast keep the footer and buttons visible; the System
Settings hand-off parks without covering the list.

## Fixture renders required for review

These are native AppKit content renders of the hosted `SetupWizardScreen`, not screen captures, and
they do not prove keyboard, VoiceOver, or manual interaction. Capture the Pet step with
“Try the sample pet first” visible, and the Pet step after it is chosen (sample-active message), in:

- English / light (`en-light`)
- Japanese / dark (`ja-dark`)

For the render, build from the worktree, use the repository example sheet as the sample
(`assets/examples/nyatinte-bot-3x3.png`, shipped as `demo-pet.png`), isolated temporary preferences,
and `cacheDisplay(in:to:)` composited on the window background. Inspect them for text and footer
clipping at the default font; the JA/dark sample-active line is the worst case.

## Automated verification

`mise run test` covers the state machine; see the tables in
[setup-wizard-qa.md](setup-wizard-qa.md). The journey-specific additions live in the
`SetupWizardJourneyTests` suite: `tryingTheSampleCommitsTheBundledSampleInPlace`,
`tryingTheSampleNeverReplacesAnExistingPet`, `importingARealSheetClearsTheSampleChoice`,
`interruptedPermissionFlowResumesToRestartRequired`, and
`deferringSavesTheReadyStepSoARelaunchCanResume`.
