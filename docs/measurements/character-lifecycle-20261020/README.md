# Character import / close baseline — 2026-10-20

## Scope and provenance

This is a pre-refactor baseline for #98, #95 and #124, **not a before/after comparison or closure
of their memory acceptance**. Product sources are unchanged from merged main
`f1a450e99ed226085e0956157df2a95308b59dbe`. The new measurement mode lives only in
`Tools/profile_image_app.swift`; its measured SHA-256 is
`459e3b5cbcd3c3d973d59b82a601bbec384879b9818485cc782f4f4f9aea4c9d` (the original probe at `d433a98`).

**Review limitation:** that probe checked `canApply` but could accept a preserved old pet after a
failed later acquisition. The CSVs below are exploratory data, not proof of nine fresh replacements.
[The follow-up](follow-up/README.md) records the stronger guard, an actual failed-acquisition check,
one corrected normal run, and a separate stack-logging investigation. Original files and medians
are preserved, not retrospectively reclassified as stronger-guard passes.

- Apple Silicon, macOS 27.0.1 (`26A434`), Apple Swift 6.4; three sequential independent processes.
- Actual AppDelegate/Core/SwiftUI sources compiled with `-O -swift-version 6` into the temporary
  `dev.nyatinte.waddly.memoryprobe` app. This is a whole-process source probe with a custom entry
  point, not the signed packaged Release executable or a physical-input walkthrough.
- Each run uses a fresh preferences suite and temporary image directory, removed on success.
  No production preferences/images were changed, no Input Monitoring grant was requested, no
  keyboard events were synthesized, and no clipboard image payload was imported.
- Same generated transparent 3072 × 3072 PNG, 677,976 bytes, SHA-256
  `73f012dc8add9366d821e9603addd680047414c34d6bdcd29737c2ac438727be`.
  Result: nine 1024 × 1024 frames, category counts 2/4/1/2. This is the **accepted large-sheet
  exception**, not a typical-sheet demonstration of the under-100 MB goal.
- Existing desktop applications were left running. Runs were sequential, but this is not an
  otherwise quiescent-machine experiment. No historical revision was measured with this workload.

## Workload and runnable checks

```sh
WADDLY_PROFILE_CHARACTER_LIFECYCLE=1 ./macos/profile-image-app.sh
```

After launch and closing the empty setup guide, repeat three cycles in the same process:

1. Open the real Change Character window; call its model's normal `stageFiles` acquisition path.
2. Require `canApply` (the original guard), then keep the staged preview visible for 30 seconds.
   The corrected current probe additionally requires `failure == nil` and `isDirty`; see the
   review limitation above.
3. Await the controller's real `applyAndClose()` task (including the serialized store commit).
4. Require a complete committed pet, a clean draft, no commit failure/rejection, a hidden window,
   and a cleared AppDelegate controller reference.
5. Wait 30 seconds, then require weak references to both the closed controller and its model to
   be nil. Failure exits the probe nonzero; all nine measured cycles satisfied these checks.

The CSV records launch plus nominal one-second samples during both 30-second holds: exactly 181
ordered samples per run. Physical footprint/RSS are `task_info` byte counters; peaks are kernel
cumulative ledgers, not just the largest sampled plateau. Scheduling and framework work may extend
nominal intervals. Cycle 0 is warmup with an initially empty pet; do not compare empty launch with
loaded-pet close as a leak delta. Stage/Apply calls bypass native picker/drag/confirmation gestures.
The advanced editor, Setup import host, invalid/cancelled imports, sharing, typing and frozen states
are not exercised.

## Three-run results

All values below are **MiB** (bytes / 1,048,576), rounded only for presentation. Closed values are
snapshots 30 seconds after each close, not interval averages. Diagnostic runs are excluded.

| Run | Peak physical footprint | Closed cycle 0 | Closed cycle 1 | Closed cycle 2 | Final RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 169.75 | 80.28 | 122.78 | 124.05 | 217.39 |
| 2 | 173.95 | 122.42 | 122.58 | 123.33 | 215.94 |
| 3 | 169.94 | 120.77 | 123.05 | 82.28 | 217.42 |
| Median | 169.94 | 120.77 | 122.78 | 123.33 | 217.39 |

The final physical-footprint median is about **129.32 decimal MB**, and the median peak about
178.19 MB. Both exceed the whole-app goal for this already-excepted large input. Return to the
first closed plateau is **not consistently demonstrated**. Physical footprint changes substantially
even during a hold: run 2 cycle 0 rises from 78.42 to 122.42 MiB, while run 3 cycle 2 falls from
124.63 to 82.28 MiB. Do not hide that variability behind the medians.

RSS at the closed cycle 1 → cycle 2 snapshots increases by 8.95, 8.92 and 9.28 MiB respectively.
This is a remaining observation to classify, not proof of an ownership leak or of bounded retention.
Controller/model destruction alone does not establish release of all framework/graphics resources.

## Separate diagnostic run

`diagnostic.csv` repeats the same workload while `vmmap -summary` and `leaks` inspect the same PID
(83324) during the first and third closed holds. Inspection can perturb memory; exclude this run
from the table above. All three controller/model weak-reference checks passed here too.

| Diagnostic (`vmmap` units as printed) | After cycle 0 | After cycle 2 |
| --- | ---: | ---: |
| CG Raster Data resident | 36.8M / 36 regions | 36.8M / 36 regions |
| CoreAnimation resident | 320K | 336K |
| Default malloc zone bytes allocated | 12.8M | 13.1M |
| Default purgeable malloc zone bytes allocated | 45.0M | 61.6M |
| `leaks` results | 416 / 19,936 bytes | 416 / 19,936 bytes |

The stable raster accounting and small ordinary-malloc change do not show accumulating complete
36 MiB frame sets at these snapshots. Purgeable allocations grow, but these category summaries do
not identify the allocation call sites or explain the entire RSS difference.

`leaks` exits **1** at both inspections: this is **not a zero-leak result**. The same reported root
cycles involve `NSXPCConnection`, `LNDaemonApplicationInterface`, and AppIntents-related blocks; the
count/bytes do not increase. Both reports warn that the process is not debuggable and access is
restricted. Do not claim an exhaustive leak audit, dismiss every result as harmless, or attribute
these cycles to Waddly without allocation stacks. No `MallocStackLogging` was enabled.

## Raw files and limits

- `run-1.csv`, `run-2.csv`, `run-3.csv`: unmodified primary samples, in execution order.
- `run-2.environment.txt`, `run-3.environment.txt`: OS/toolchain, product HEAD, probe/fixture hashes
  and the compiled source-file hashes captured by the script. Run 1 preceded the environment emitter
  addition; it has **no contemporaneous environment sidecar**. The probe Swift file was unchanged
  between the three runs. Do not invent missing run-1 metadata.
- `diagnostic.csv`, `diagnostic.environment.txt`: fourth run and source provenance.
- `cycle-{0,2}-{vmmap,leaks}.txt`: unmodified inspection reports. `environment.txt` records PID,
  original local CSV path and inspection exit statuses; that CSV is copied here as `diagnostic.csv`.
- The existing macOS sandbox-extension warning appeared during temporary-app launch; all four probe
  processes completed successfully and self `task_info` calls succeeded. No permission workaround
  was applied. A successful probe is not a `leaks` pass.

Validation: formatting, localization checks/strict lint, complexity, safety checks/fixtures,
completion-guard fixtures and `mise run build` passed. `mise run memory:test` completed normally:
one allocation-budget test passed and the opt-in strict leak test was skipped as configured.
`mise run test` **failed** after starting `SetupWizardCharacterImportTests.closingTheWizardConfirmsDiscardOfADirtySharedDraft`;
the guard rejected two starts with only one completion (#131). No retry-until-green or reduced
full-test selection was used.

The [follow-up](follow-up/README.md) now supplies selected allocation-stack evidence and corrects
the acquisition guard. A longer corrected workload and a suitable historical comparison are still
needed before claiming bounded retention or no regression. Keep #98/#95/#124 open; the original
records narrowly verify closed-session release, not every intended acquisition.
