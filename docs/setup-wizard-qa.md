# Setup Guide state reference and QA matrix

The Setup Guide renders the SwiftUI `SetupWizardScreen` inside an AppKit window that keeps the fixed
820 × 520 pt layout. This page lists the states the guide can show, what the automated suites verify
today, and the manual checks that remain unverified. It contains no captures and no manual QA
results; treat the two tables below separately.

## States

| Screen | State | Primary action | Other actions |
| --- | --- | --- | --- |
| Pet | No image yet | Create with ChatGPT / Choose a PNG | Drag and drop a PNG onto the window; sample pet plays in the preview |
| Pet | ChatGPT guide | Copy the prompt and open ChatGPT | Choose a PNG, Change method, inline copy/open status |
| Pet | Image registered | Next | Change image (imports immediately and replaces the saved set) |
| Any step | Import failed (drop or picker) | Choose a PNG again | Inline message in the page column; nothing is written and the previous set stays; clears when the step changes |
| Keyboard reactions | Not granted | Enable Input Monitoring | Privacy note; guide opens System Settings and parks beside it; manual steps remain available |
| Keyboard reactions | Granted, not yet receiving | Restart Waddly | Try again without restarting; Next stays disabled and “Set up later” is the non-destructive escape |
| Keyboard reactions | Granted and receiving | Next | “If it does not work” troubleshooting stays in the window |
| Ready | Finished, permission ready | Show on desktop | Pet check and monitoring check both filled |
| Ready | Finished, permission missing | Set up Input Monitoring | Warning line; never visually impersonates success |

Inline status text is used instead of a modal alert for two paths: the copy/open result on the
ChatGPT guide (`copied` / `copy failed` / `open failed`) and an unreadable pet sheet. The window-wide
drop target stays live on every step, so the import message is shown in the page column on the step
where the drop happened and clears when the step changes. When an error appears, the wizard posts one
native accessibility announcement with the localized message; re-rendering never re-announces. The
wizard reads a chosen sheet and, if the read succeeds, commits it immediately — there is no
review-before-write step and no wizard confirm dialog. A failed read writes nothing and keeps the
previous set.

## Automated verification (verified)

Command: `mise run test` (serialized Swift Testing suites). The wizard suites are
`SetupWizardTests`, `SetupWizardPreviewTests`, `SetupWizardDropTests`, and `PermissionServiceTests`.

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
| Permission rules, polling, manual steps, and deferral | `PermissionServiceTests` |

## Manual QA matrix (unverified)

These need a real GUI session, VoiceOver, and Input Monitoring in System Settings. They have **not**
been run in this workspace and are listed here so a reviewer can complete them; do not record them as
passed until they are actually executed on the target machine.

| Check | State to exercise | Expected |
| --- | --- | --- |
| VoiceOver status wording and failure announcement | Not granted → granted-not-receiving → ready; then trigger a failed import | Each status label reads the current state once when reached, and an inline failure is spoken once without repeating on re-render. The announcement call is unit-tested; the actual speech is not, and must be heard here |
| Larger text | All Pet and Keyboard reactions states | Content wraps without clipping or hidden buttons |
| Import failure banner | Any step, including the ChatGPT guide with open-failure text | Banner and page do not overlap the footer. Default-font English/light and Japanese/dark native renders were inspected; other states and larger text still need a manual pass |
| Increased contrast | All states, light and dark appearance | Status and inline errors stay distinguishable from body text |
| Reduce Motion | Step transitions | No cross-fade; layout still stable |
| Keyboard only | Pet, Keyboard reactions, Ready | Tab reaches every action; Space/Return activate; focus never jumps to a different control after a status update |
| Real System Settings hand-off | Not granted | Guide parks beside the list without covering it; manual steps still reachable if drag fails |
| Browser hand-off | ChatGPT guide | With a browser available, ChatGPT opens and the inline text says the prompt was copied; with no handler, the inline open-failure message appears |
| Invalid sheet | Any step | An unreadable PNG shows the inline message on that step and leaves any previously imported pet in place |
| Both languages | All states | English and Japanese copy fit the fixed columns |
