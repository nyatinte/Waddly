# Setup Guide state reference and QA matrix

The Setup Guide renders the SwiftUI `SetupWizardScreen` inside an AppKit window that keeps the fixed
820 × 520 pt layout. This page lists the states the guide can show, what the automated suites verify
today, and the manual checks that remain unverified. It contains no captures and no manual QA
results; treat the two tables below separately.

## States

| Screen | State | Primary action | Other actions |
| --- | --- | --- | --- |
| Pet | No image yet | Create with ChatGPT / Choose a PNG | Try the sample pet first (bundled sample, offered only while no pet is stored and no import is still committing); drag and drop a PNG onto the window; sample pet plays in the preview |
| Pet | ChatGPT guide | Copy the prompt and open ChatGPT | Choose a PNG, Change method, inline copy/open status |
| Pet | Image registered | Next | Change image (opens the shared character screen; Continue applies the staged sheet) |
| Pet | Sample in use | Next | Change image; the page states the sample is active so it is not mistaken for the user's own pet |
| Any step | Import failed (drop or picker) | Choose a PNG again | Inline message in the page column; nothing is written and the previous set stays; clears when the step changes |
| Keyboard reactions | Not granted | Enable Input Monitoring | Privacy note; guide opens System Settings and parks beside it; manual steps remain available |
| Keyboard reactions | Granted, tap unavailable | Restart Waddly | Try again without restarting; Next stays disabled and “Set up later” is the non-destructive escape |
| Keyboard reactions | Tap live, no key delivered | (press a key) | “waiting for a key press”; pet is awake in the preview; Next stays disabled until a real key reaches Waddly |
| Keyboard reactions | Key delivered (confirmed) | Next | “If it does not work” troubleshooting stays in the window |
| Ready | Finished, reactions confirmed | Show on desktop | Pet check and monitoring check both filled |
| Ready | Finished, reactions unconfirmed | Confirm typing | “waiting for a key press” check line and a “press a key” warning; never visually impersonates success |
| Ready | Finished, permission missing | Set up Input Monitoring | Warning line; never visually impersonates success |

Inline status text is used instead of a modal alert for two paths: the copy/open result on the
ChatGPT guide (`copied` / `copy failed` / `open failed`) and an unreadable pet sheet. The window-wide
drop target stays live on every step, so the import message is shown in the page column on the step
where the drop happened and clears when the step changes. When an error appears, the wizard posts one
native accessibility announcement with the localized message; re-rendering never re-announces.
Choosing a PNG or Change image opens the shared character screen inside the Pet step. A chosen,
pasted, or dropped sheet is staged and previewed there; the step's Continue applies it once, so no
review-before-write step was added, but nothing is written before Continue either. A failed read or
paste shows an inline reason and keeps the staged candidate and saved pet; a failed save shows an
inline retry, keeps the draft, and stays on the step. A window-wide drop outside the shared screen
(for example on the Keyboard reactions step) still uses the direct import path, which writes on a
successful read. In the Change Character window, Apply commits the staged draft and closes only on
success; a failed save remains retryable.

## After setup: Input Monitoring settings

When image + seen + cleared step indicate finished setup, both menus offer **Set Up Input Monitoring…**.
The existing permission page opens directly in settings mode, without the step indicator, Back,
Later or completion page. **Close** is always available (Escape shortcut), including when permission
is missing. Both image-drop registrations are removed, and the window-drop handler refuses imports.
The existing permission/retry/restart/troubleshooting behavior and paused-tap rules are reused.
Opening, navigating, or closing this mode does not write setup progress or the saved character.
First-run and incomplete saved steps keep the normal Setup Guide and navigation unchanged.
Paired JA/EN light/dark [content-view renders and native-attempt limitations](images/input-monitoring-settings/README.md)
are recorded separately; they are not live permission or accessibility acceptance.

## Automated verification (verified)

Command: `mise run test` (serialized Swift Testing suites). The wizard suites are
`SetupWizardTests`, `SetupWizardJourneyTests`, `SetupWizardSampleGuardTests`,
`SetupWizardPreviewTests`, `SetupWizardDropTests`, `SetupWizardImportFeedbackTests`,
`SetupWizardCharacterImportTests` (the shared screen hosted in the Pet step), and
`PermissionServiceTests`. The shared screen model is covered by `CharacterImportModelTests`; its
render fixtures are listed in `docs/images/character-import/README.md`.

| Behavior | Test |
| --- | --- |
| Hosted SwiftUI screen keeps the designed window size through every step, in both languages | `hostsSwiftUIAndKeepsItsDesignedWindowSize` |
| Step changes are recorded; finishing clears the saved step and hands the pet to the desktop | `stepChangesPersistAndFinishHandsThePetToTheDesktop` |
| Next cannot advance the Pet step without an image | `setupCannotAdvanceWithoutAnImage` |
| Permission request enters the guide and the manual fallback, and toggles back | `permissionActionEntersTheGuideAndManualFallback` |
| Import updates the observed state without changing the step | `importUpdatesTheSwiftUIObservedStateWithoutChangingTheStep` |
| Saved step restores; the ChatGPT guide opens and closes | `savedStepAndChatGPTGuideCanBeRestoredAndDismissed` |
| Troubleshooting stays in the window | `troubleshootingStaysInTheWizard` |
| Window-wide and preview drop targets are registered | `hostedWizardRetainsWindowWideAndPreviewDropTargets` |
| Import registers the sheet; an unreadable sheet leaves the previous set and preview alone | `choosingASheetRegistersItRightAway`, `unreadableSheetLeavesThePreviousSetAlone`, `failedImportExplainsTheProblemInlineAndKeepsThePreviousSet` |
| Closing stops preview and permission; a reopened wizard resumes playback | `closingTheWindowStopsPreviewAndAReopenedWizardCanResumeIt` |
| Copy+open reports open failure inline and success as copied | `copyingThePromptReportsCopyAndBrowserOpenResults` |
| A dark/light appearance change preserves the active drag border | `appearanceChangePreservesTheActiveDropHighlight` (state-driven, not a live drag) |
| Suspended failures cannot restore a banner/announcement after navigation, method changes, or a newer import | `SetupWizardImportFeedbackTests` (continuation-gated previews) |
| A failed import reports inline and keeps the previous set; switching method clears it | `failedImportExplainsTheProblemInlineAndKeepsThePreviousSet` |
| A failure from a window-wide drop survives on a later step and clears on step change | `importFailureStaysOnItsStepAndClearsWhenTheStepChanges` |
| An inline failure posts one announcement with the localized message; success posts none | `failedImportExplainsTheProblemInlineAndKeepsThePreviousSet`, `copyingThePromptReportsCopyAndBrowserOpenResults` |
| Preview backdrop and border re-resolve when the effective appearance changes | `previewBackdropFollowsAnAppearanceChange` |
| Granted and ready stay distinct; Next is blocked until keys actually arrive | `permissionGrantedAndReadyStayDistinctStates` |
| A live tap with no delivered key stays “waiting for a key press” and cannot advance; a delivered key confirms it | `aLiveTapStaysUnconfirmedUntilAKeyArrives`, `aLiveTapWithoutADeliveredKeyIsAwaitingReaction` |
| Missing permission, unavailable tap, waiting, and observed are four distinct states | `readinessSeparatesMissingPermissionFromAnUnavailableTap`, `aLiveTapWithoutADeliveredKeyIsAwaitingReaction` |
| “Set up later” from a live-but-unconfirmed tap keeps the check waiting and offers Confirm typing | `deferringFromALiveTapKeepsTheCheckWaiting`, `deferringDoesNotConfirmReactions` |
| A returning user who already confirmed reactions keeps that state | `aReturningUserKeepsAConfirmedReaction` |
| A fresh event tap has observed nothing | `aFreshKeyboardMonitorHasObservedNothing` |
| A stopped tap (paused app) cannot confirm a reaction | `aStoppedTapCannotConfirmAReaction` |
| A sample commit is refused once any pet is stored, even from a reopened guide | `aSampleCommitIsRefusedOnceAPetIsStored`, `aReopenedWizardCannotSampleOverAUserImportStillCommitting` |
| The sample shortcut commits the bundled sample in place, keeps the step, and is offered only when no pet is stored and no import is pending; a real import clears the sample choice and is never replaced by a sample click | `tryingTheSampleCommitsTheBundledSampleInPlace`, `tryingTheSampleNeverReplacesAnExistingPet`, `importingARealSheetClearsTheSampleChoice`, `sampleIsIgnoredWhileAUserImportIsStillCommitting`, `aFailedImportReleasesTheSampleShortcut` |
| Two rapid sample clicks start one commit | `rapidSampleRequestsCommitOnce` |
| A relaunch mid-permission resumes at “restart required”, not a false ready state | `interruptedPermissionFlowResumesToRestartRequired` |
| “Set up later” records the Ready step so a relaunch resumes with the warning still shown | `deferringSavesTheReadyStepSoARelaunchCanResume` |
| Permission rules, polling, manual steps, and deferral | `PermissionServiceTests` |
| Both existing menu copies update after completion; settings opens directly, refuses navigation/imports, closes without changing setup or saved bytes | `configuredMenusOpenMonitoringWithoutRewritingSetupOrImages` |
| Fresh setup and every saved unfinished step retain the original entry and navigation | `firstRunStillStartsWithCharacterSetup`, `unfinishedSetupKeepsItsMenuAndSavedStep` |
| Settings mode preserves all four permission/readiness states and injected recovery actions in JA/EN; closing does not save progress or commit images | `permissionPageKeepsAllReadinessAndRecoveryStates` |

## Manual QA matrix (unverified)

These need a real GUI session, VoiceOver, and Input Monitoring in System Settings. They have **not**
been run in this workspace and are listed here so a reviewer can complete them; do not record them as
passed until they are actually executed on the target machine.

| Check | State to exercise | Expected |
| --- | --- | --- |
| VoiceOver status wording and failure announcement | Not granted → tap unavailable → waiting for a key → confirmed; then trigger a failed import | Each status label reads the current state once when reached, and an inline failure is spoken once without repeating on re-render. The announcement call is unit-tested; the actual speech is not, and must be heard here |
| Larger text | All Pet and Keyboard reactions states | Content wraps without clipping or hidden buttons |
| Import failure banner | Any step, including the ChatGPT guide with open-failure text | Banner and page do not overlap the footer. Default-font English/light and Japanese/dark native renders were inspected; other states and larger text still need a manual pass |
| Increased contrast | All states, light and dark appearance | Status and inline errors stay distinguishable from body text |
| Reduce Motion | Step transitions | No cross-fade; layout still stable |
| Keyboard only | Pet, Keyboard reactions, Ready | Tab reaches every action; Space/Return activate; focus never jumps to a different control after a status update |
| Real System Settings hand-off | Not granted | Guide parks beside the list without covering it; manual steps still reachable if drag fails |
| Real typing confirmation | Tap live, then type | The step stays “waiting for a key press” until a key actually reaches Waddly, then flips to confirmed and enables Next |
| Relaunch after closing | Complete pet, closed mid-step | A relaunch does not reopen the guide; a Dock click or Setup Guide… resumes the saved step |
| Browser hand-off | ChatGPT guide | With a browser available, ChatGPT opens and the inline text says the prompt was copied; with no handler, the inline open-failure message appears |
| Invalid sheet | Any step | An unreadable PNG shows the inline message on that step and leaves any previously imported pet in place |
| Both languages | All states | English and Japanese copy fit the fixed columns |

See [setup-first-run-journey.md](setup-first-run-journey.md) for the audited journey map, the
state-transition invariants, and the five scripted first-run tasks to run against a real GUI session.
