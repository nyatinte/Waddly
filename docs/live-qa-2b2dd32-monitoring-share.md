# Bounded native monitoring / Share QA at `2b2dd32`

Follow-up of [#111](https://github.com/nyatinte/Waddly/issues/111). Scope deliberately excludes
[#151](https://github.com/nyatinte/Waddly/issues/151) and its character/crop editor. This is QA evidence
and one bounded visual finding, **not** full keyboard/VoiceOver or consolidated acceptance.

## Environment / isolation

- Product source: `2b2dd32813f36620707657130874a83bb9265a96`; no production/test Swift or workflow
  edits for these observations. `macos/build-development.sh` built and signed the isolated app.
- Apple Silicon, macOS 27.0.1 (`26A434`), Swift 6.4. ScreenCaptureKit snapshots report scale 2.
- Actual app: `dev.nyatinte.waddly.qa111b.development`, under ignored `dist/qa111b/`, its own
  preferences and `Waddly-qa111b.development/PetImages`; public bundled sample chosen through Setup.
- Fixture app: `dev.nyatinte.waddly.qa111b.fixture`; unchanged production Share controller/views/Core
  with a custom main, UUID localization suite, app-only appearance and injected system effects.
  The copied bundle's display name still says `Waddly (qa111b.development)`; bundle ID distinguishes it.
- Actual-app EN/dark; fixture EN/light and JA/dark. Not all four language×appearance combinations.
  Actual window sizes: monitoring 820×548 pt; stock Share 700×438 pt. Custom-host Share is 700×442 pt
  including its differently styled title bar, with unchanged 700×410 pt content constraints. This is
  not evidence of product-state window resizing or a paired title-bar comparison.
- Orca reports Accessibility and screen capture granted; menus/menubar/Dock are not supported
  surfaces in that provider. Native AX helpers were used for status commands and attributed names;
  a topmost-owner-checked CGEvent helper opened the pet context menu.
- Ten [native captures, receipts and archived helpers](images/monitoring-share-qa-2b2dd32/README.md).
  No OS permission, login, global appearance, contrast, Full Keyboard Access or Reduce Motion setting
  changed. No normal-app process/data was targeted. The fixture's copy/browser hooks never invoke
  the real clipboard or browser. Both isolated apps stopped after QA; language/suite overrides cleaned.

## Executed observations

| ID | Input / path | Observed result | Evidence |
| --- | --- | --- | --- |
| M1 | Actual app: sample → Next → Set up later → Show on desktop; status menu → Set Up Input Monitoring | Direct permission page; not allowed/off; no onboarding progress, Back, Later or Next; Close present | `monitoring-en-dark.png`, native attributed-label receipt |
| M2 | Explicitly target monitoring window ID, restore it, then synthetic Escape | Post-action AX/WindowServer inventory no longer contains the settings window; no focused/main window remains | `settings-escape.json`, `settings-after-escape.txt` |
| M3 | Reopen from native menu, read Close label, AXPress Close | Settings window disappears; pet remains; saved image/manifest hashes and preferences unchanged | `settings-reopened.json`, `settings-close-action.txt`, `settings-after-close.txt`, before/after receipts |
| S1 | Actual app: verified-owner synthetic right-click → Share Pet AXPress | Real export reaches ready state, 700×438 pt window; no browser/clipboard action | `share-stock-en-dark.png`, context/action receipts |
| S2 | Live fixture: hold first generation, then release injected failure | Working spinner and disabled Post; failure text + enabled Try Again, Post still disabled, in both executed locales | working/failed captures |
| S3 | AXPress Try Again / 再試行 | Same window returns to generated video + sheet with posting enabled; this attempt uses the real exporter | ready captures + retry-action receipts |
| S4 | Fixture: AX copy action / post action with failure-returning effect | Per-asset and composer inline failures appear; original actions remain present; full text exists in AX | EN/light errors and JA/dark errors captures/receipts |
| S5 | Inspect default-size JA/dark errors | Recovery text tails are visibly ellipsized for both copies and composer help | **Confirmed visual finding [#154](https://github.com/nyatinte/Waddly/issues/154)** |
| C1 | Actual app image/manifest hashes and preferences after isolated onboarding, before monitoring, after M3 and after Share | Exact before/after matches; no character/setup mutation from monitoring or Share | archived before/after plist and hash receipts |

AXPress receipts themselves report only an accepted/unasserted action. Results above are based on
subsequent window/AX/pixel observations, not that return code alone. Likewise, the synthetic Escape
request was unverified by the provider; the later disappearance is the observed effect, **not a
physical keyboard pass**.

The earlier monitoring-window acquisition blocker did not prevent this bounded run: after the menu
action, explicit window-ID targeting, allowing the window to settle and restoring it exposed the
actual window/tree. The first immediate list was empty and an untargeted snapshot selected the pet
panel. This does **not** establish the root cause of the earlier acquisition failure or a product fix.
An earlier Escape request without the settings-window selector had no established dismissal; it is
not counted as a failed product Escape test.

## Controlled outcomes versus real system failures

The Share fixture holds its first `writeMovie` hook until a QA sentinel exists or a 60-second fail-safe
expires, then throws a fixture error. Retry forwards to the real `PetShareExporter`. Copy image returns
false, movie publication returns nil, and browser opening returns false. These deliberately surface
production failure views while avoiding clipboard/browser side effects. They establish rendering and
native action-to-state transitions, not actual clipboard compatibility, OS failure recovery, native
writer/service root cause, or speech output. No #143 reproduction, fix or reopen is claimed.

An initial attempt to induce an **actual filesystem failure** by launching the stock app with a private
`TMPDIR` and moving that scratch directory did **not** establish the fault: the stock app still exported
successfully and the scratch directory contained no assets. The child environment did contain that
TMPDIR value. No filesystem-failure/retry success is claimed from this attempt, and its ready capture
is retained as stock success, not mislabeled as a failure. No global temp directory was modified and
no filesystem or OS privacy permissions were changed to force the test.

Synthetic Escape and Command-W requests while stock Share was focused did not dismiss that window.
The input requests are provider-unverified; this alone does not demonstrate physical delivery or a
product keyboard defect. Physical shortcuts/focus traversal remain pending. Share was subsequently
closed through its native close button; fixture close also ended its process and cleaned its suite.

## Finding / next boundary

[#154](https://github.com/nyatinte/Waddly/issues/154) tracks **visually truncated Japanese Share recovery
instructions at the standard footprint**. The AX tree retains complete messages, so the finding is not
missing accessible text or proven failed announcement. Source corroborates the visual result:
`PetShareCardView` and the composer status label explicitly truncate tails; the copy status shares a
row with format text, and the centered post button constrains status to the row's right-hand space.
The EN/light capture fits its shown image/browser errors; that is not a general long-label guarantee.

Fix acceptance should retain the complete JA/EN instructions without widening the window or changing
actions/accessibility semantics, with layout regression coverage and paired native captures. This
report does not implement that change or claim #154 fixed.

## QA infrastructure failure (not suppressed)

The first custom fixture launch (PID 30453, local 2026-10-22 00:02:41) aborted in dyld before application
code: the helper executable referred to `dist/qa111b/fixture-core/libWaddlyCore.dylib` relatively, which
LaunchServices could not resolve. The helper's install names were corrected to `@rpath` and its explicit
rpath, library and app re-signed, then native windows were observed in PIDs 33281 and 41753. The user saw
the crash report and was informed of this QA packaging error. This is neither a shipping-app crash nor
a product test failure retried away. The archive documents the corrected replay recipe and hashes;
it does not publish the raw machine-identifying OS crash report.

## Still unverified / completion boundary

- Physical Tab/Shift-Tab/Space/Return/Escape/Command-W traversal, focus order/rings, held press and
  spoken VoiceOver (including whether complete failure messages are announced).
- Monitoring permission grant/restart/reaction journeys and all four readiness states live; this run
  only observed not-allowed/off and did not click the permission request.
- Native Finder drop rejection on monitoring settings: **not attempted in this session**. Existing
  programmatic coverage is not a substitute for that acceptance check.
- Real clipboard/browser failures and paste/composer compatibility; no post published or attachment sent.
- Increased contrast, Reduce Motion, larger text, smaller actual display/work area, full appearance
  cross-product, and all other #111 screens, particularly the changing #151 editor.
- Image lifecycle budget/attribution remains #98. #143's owner disposition is independent.

No full product test suite was run or represented as passing in this documentation-only QA work.
The actual development build, fixture Core/app compilation and signing succeeded after the documented
helper packaging correction. Check archive hashes and `git diff --check` separately. #111 stays open.
