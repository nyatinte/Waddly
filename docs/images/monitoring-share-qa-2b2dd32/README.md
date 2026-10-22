# Native monitoring / Share QA captures

For [#111](https://github.com/nyatinte/Waddly/issues/111), product source
`2b2dd32813f36620707657130874a83bb9265a96`. Full scope, observations and limitations:
[QA report](../../live-qa-2b2dd32-monitoring-share.md).

These ten PNGs are **ScreenCaptureKit captures of visible native windows**, not `cacheDisplay`
renders. The JSON in `receipts/` retains the captured-window IDs, scale, AX tree and action receipts.
Capture-file paths inside those receipts are historical temporary paths; the adjacent named PNGs
are the retained images. `environment.txt` records source, OS/toolchain, public fixture and corrected
Share-fixture binary/library hashes. `SHA256SUMS` covers this archive except itself.

| File | Configuration / boundary |
| --- | --- |
| `monitoring-en-dark.png` | Actual isolated development app; completed setup; permission not allowed; standard 820×520 pt content / 820×548 pt window |
| `share-stock-en-dark.png` | Actual isolated app; successful export; **the attempted TMPDIR fault did not establish a failure** |
| `share-fixture-en-light-working.png` | Live production controller; first generation deliberately held; posting disabled |
| `share-fixture-en-light-failed.png` | Injected generation failure; Try Again visible; posting disabled |
| `share-fixture-en-light-ready.png` | Try Again invoked through AX; second attempt used the real exporter |
| `share-fixture-en-light-errors.png` | Injected image-copy and browser failures; no clipboard write/browser open |
| `share-fixture-ja-dark-working.png` | Japanese/dark counterpart, deliberately held generation |
| `share-fixture-ja-dark-failed.png` | Japanese generation error / Retry |
| `share-fixture-ja-dark-ready.png` | Japanese Retry returned to real generated assets |
| `share-fixture-ja-dark-errors.png` | Both copy errors plus browser error; visible tail truncation tracked in [#154](https://github.com/nyatinte/Waddly/issues/154) |

The Share fixture uses unchanged production views/controller/Core sources but replaces AppMain with
`share-fixture.swift.txt`. It sets only its own app appearance and UUID-scoped localization settings,
injects one generation failure via `PetShareEffects.writeMovie`, then uses the real exporter on retry.
The copy/publication/browser effects deliberately return failure. No shared clipboard is read or
written and no browser/composer is opened by this fixture. **These are controlled effect outcomes,
not actual OS clipboard/browser faults or reproduction of #143.** Only EN/light and JA/dark were
executed, not the full locale×appearance cross-product.

`build-fixture.sh.txt` is a replay recipe for the **corrected** helper, using the product sources from
that revision plus this archive. It was assembled after capture, not executed as one script during
the session. It sets the library install name to `@rpath/libWaddlyCore.dylib` at compile time. The actual
session initially omitted that setting: helper PID 30453 aborted in dyld before AppMain at local
2026-10-22 00:02:41, missing a relatively named dylib. The helper/library install names were corrected
with `install_name_tool` and both were re-signed before any retained fixture captures. Corrected
processes 33281 and 41753 displayed the recorded windows. This **QA packaging failure** is retained
as a limitation, not a product crash or a passed test; the raw OS crash report containing machine
identifiers is intentionally not published.

Other archived helpers:

- `menu.swift.txt`: own-bundle native menu inspection / AX command activation. Status-menu AXPress
  returned `-25204` while child items became readable; item AXPress returned 0. Neither alone is
  proof of navigation; the later actual window/AX state is the observation.
- `context.swift.txt`: CGEvent right-click, guarded by a fresh WindowServer topmost-owner check.
- `windows.swift.txt`: own-PID AX/WindowServer inventory.
- `attributes-and-action.swift.txt`: pre-existing helper reused for attributed labels and semantic
  Close. It has force unwraps; use only after confirming the exact app/window. No retained run of
  this helper crashed. It also contains older drag modes **not executed in this session**.

All helpers are QA artifacts, not product code. No key-code collector was added. Window IDs and
hardcoded coordinates/bundle IDs are session-specific, not a reusable general automation framework.
Both isolated apps were stopped after checks; the temporary language override was removed and
UUID localization suites removed on fixture close. Sampled image/manifest hashes and isolated
preferences matched before/after monitoring and Share (before removing that language override).
No normal-app data or TCC, login, system appearance/accessibility settings were changed.
