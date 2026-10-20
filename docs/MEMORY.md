# Repeatable memory measurements

The production goal is **less than 100 MB of physical footprint** in representative supported configurations. Record RSS as context, too: it includes shared resident pages, while macOS physical footprint accounts for the process's charged physical memory (including compressed memory). Neither equals the allocator's live-byte delta used by the regression suite. A single startup reading does not establish a budget for arbitrary numbers of user images.

**Accepted exception for 1.0:** importing a very large sheet (for example a transparent 3072 × 3072 sheet with nine 1024 × 1024 frames) exceeds the 100 MB footprint goal. The paired probe measured a peak of about 134 MB and a final plateau of about 104 MB on macOS 27.0.1, and the memory reduction work in #34 / #40 / #41 did not close the gap. The 1.0 release accepts this exception and keeps the under-100 MB goal for typical use. Revisit the residency policy before raising the supported image limits or claiming the footprint goal for large images.

## Release app workflow (macOS 14+, Apple Silicon)

Use the same Mac, OS, input images, app settings, and sample duration for a before/after comparison. Quit other Waddly instances, build with `mise run build`, and launch `build/Waddly.app`. Get its PID with `pgrep -x Waddly`; use the single PID throughout the run. The sampler does not start/stop the app, change preferences, or synthesize keyboard events.

```sh
./macos/profile-memory.sh PID launch-idle 30
```

Replace `PID` with the process ID. Results go to `dist/memory/TIMESTAMP-LABEL/`: `rss.csv` has one-second RSS samples in KiB, `summary.txt` has mean and peak RSS in MiB, `footprint.txt` has one-second footprint samples in bytes, and `environment.txt` records OS, architecture, commit, command, and process age. Inspect footprint failures in the log; if macOS denies inspection, use an authorized terminal for the same command. Keep the raw files with the comparison; short spikes between samples can be missed.

Run these scenarios in order for each commit:

| Label / duration | Actions during or before sampling |
| --- | --- |
| `launch-idle` / 30 seconds | Use the example sprite sheet; record the time since launch. Avoid typing after selecting the app. |
| `typing` / 30 seconds | Type normally in a text editor, including Enter. No text or key codes are collected by this workflow. |
| `image-heavy` / 30 seconds | Import a transparent 3072 × 3072 sheet (nine 1024 × 1024 frames). Open image settings to include thumbnails. Record file hash, size, dimensions, and actual frame counts. |
| `repeated-imports` / 60 seconds | Reimport that same sheet ten times, confirming each preview; then add, reorder, and remove one per-category image. Keep the final frame counts equal to the initial counts. |
| `return-idle` / 30 seconds | Close image settings and stop typing. Compare with `image-heavy` and repeat the import cycle if memory still rises. Allocator caches need not immediately return pages to the OS. |
| `sleep-frozen` / 360 seconds | Do not type for the entire sample. Includes idle, sleep at 25 seconds, and frozen at 325 seconds after last activity. Watch for sustained growth after frames stop changing. |

Repeat three runs per commit and compare the median of each run's mean and peak, plus the footprint plateau at the end. Report configuration, raw measurements, and both transient peak and final plateau. Do not claim a pipeline improvement using only the allocator numbers below.

For diagnosis, keep the same process and scenario:

```sh
footprint -p PID -f bytes
vmmap -summary PID
leaks PID
```

In Instruments, attach Allocations or VM Tracker to the Release app, mark generations before/after imports, and examine persistent allocations and decoded image backing stores. Use Leaks to investigate suspected ownership leaks; a positive retained-byte delta alone is not proof of a leak.

## Isolated regression suite

```sh
mise run memory:test
```

`Performance/` is a separate package with exact dependency versions and a checked-in `Package.resolved`. The tagged `swift-testing-performance` 0.3.1 manifest requires **Swift 6.2 and macOS 26**, despite its README advertising macOS 15. The test harness follows the manifest; the production package and Release app remain macOS 14 and contain no performance dependencies. CI runs this command in a separate macOS 26 job.

The serialized suite generates a transparent 3072 × 3072 PNG and warms the complete import/save/reload path in a suite preparation trait, before measurement baselines are captured. The immutable fixture is shared across iterations. Autorelease pools drain between replacements; tests use a temporary directory and never touch app preferences or user images.

`@Test(.trackPeakMemory(limit: 64 * 1024 * 1024))` runs ten iterations, with two imports per iteration. In the pinned implementation, this trait samples after each iteration. An additional `PeakMemoryTracker` samples while decoded frames and reloaded images are still alive and enforces the same 64 MiB incremental live-byte budget. The first measured iteration recorded 59,978,352 bytes (57.2 MiB) after the complete warmup, with subsequent iterations around 0.91 MiB. The limit allows about 12% headroom over the first-iteration allocator result. It is independent of the 40 MiB production residency policy and the 100 MB total-process footprint goal.

Strict allocation-growth leak detection remains available diagnostically:

```sh
WADDLY_EVALUATE_LEAKS=1 mise run memory:test
```

The pre-refactor warmed scenario passed `.detectLeaks()` (via `.timed(detectLeaks: true)`). With eagerly decoded, independently owned frames, repeated evaluations reported 13 net allocator blocks / 2,840 bytes even after complete warmup, while later import iterations remained stable and the process probe returned to a fixed plateau. This small process-wide delta is consistent with framework/runtime caches, although its allocation stacks have not been classified. It makes the strict zero-growth trait unsuitable as a default CI gate for the new path. The normal suite keeps the bounded allocation guard; diagnose suspected ownership leaks with `leaks` and Instruments rather than treating a small block delta as proof. VM-backed ImageIO/CoreGraphics buffers can also escape malloc statistics, so the process workflow remains essential.

## Baseline and budgets

Baseline collected on 2026-10-04, Apple Silicon, macOS 27.0.1 (26A434), Release optimization, production source at `64729d8`:

| Measurement | Result | Limit / interpretation |
| --- | --- | --- |
| Sampled image pipeline allocator delta, images alive | 935,536–935,600 bytes | 2,000,000 bytes: a little over 2× measured baseline, allowing framework/runtime variation |
| Warmed leak scenario (three iterations) | Passed; reported end-of-iteration peak 0 bytes | No positive net allocator block growth |
| Earlier Release app startup/idle measurements (macOS 27.0) | RSS 52,176–52,416 KiB (about 51 MiB); physical footprint about 12–13 MB | Historical context only; typing/heavy/long-running states were not measured then |

The 2 MB guard is an incremental allocator budget, **not** a 2 MB total-app or image-pixel budget. The app goal remains under 100 MB physical footprint. Full lifecycle process baselines must be collected with the workflow above before changing the image residency policy or claiming before/after peak-memory savings.

## Image pipeline comparison and residency policy (#34)

Run the same optimized standalone process probe against a historical revision and the current source:

```sh
./macos/profile-image-pipeline.sh d9c24d6
./macos/profile-image-pipeline.sh
```

The probe generates the same transparent 3072 × 3072 sheet, imports all nine frames five times, materializes the preview, atomically writes every PNG, and retains the previous frame set during replacement. It collects RSS, physical footprint, and kernel peak ledgers through `task_info`, plus `getrusage` peak RSS. Raw CSV files go to `dist/memory/`. The historical revision uses its actual full-resolution `NSImage(data:)` preview; the current path uses the thumbnail API. This measures the image pipeline, not AppKit windows, input monitoring, or a whole-app sustained lifecycle.

Two paired optimized runs on Apple Silicon / macOS 27.0.1 produced these representative results (MiB):

| Pipeline | Peak RSS | Peak physical footprint | Final physical footprint |
| --- | ---: | ---: | ---: |
| Before (`d9c24d6`) | 351–353 | 261–263 | 192–194 |
| After (this change) | 221 | 89 | 48 |

The measurements use the deterministic generated PNG, not user images. Raw CSV samples are not retained in the repository.

The new path thumbnails the preview to 480 px, directly encodes CGImage as PNG, eagerly decodes on workers, and owns each extracted frame independently. Independent buffers prevent a remaining cropped frame from retaining the complete original sheet. Atomic writes are staged and rolled back on failure; the committed manifest is written atomically before the UI state is published and workers sweep unreferenced files. Reorders and removals reuse persisted filenames, and individual imports reuse their optimized PNG bytes. A main-actor queue serializes entire transactions, including worker waits and the manifest commit (run on a worker).

Production image sets are limited to an estimated **40 MiB**, computed from each independently decoded frame's row stride × height plus **192 KiB per frame** reserved for image wrappers, view/codec metadata, and a settings thumbnail. This rounds up the approximately 0.95 MB warmed allocator overhead divided across nine frames plus at most 64 KiB for a 128 × 128 RGBA8 thumbnail. The fixed allowance bounds the number of tiny images to at most 213. Pixel buffers use their actual depth and stride, including 16-bit PNGs, rather than assuming four bytes per pixel.

The nine-frame 1024 × 1024 RGBA8 case occupies about 37.7 MiB under this policy. The standalone probe's peak was about 89 MiB, but this does **not** establish the 100 MB whole-app goal: AppKit windows, layer textures, and runtime caches add substantial memory. The policy bounds decoded frame residency, not total process footprint or replacement peaks. Existing PNG file-size, transparency, source-dimension validation, category ordering, and animation timing remain intact.

Budget checks run on worker snapshots before committing. An excessive addition leaves the committed images and manifest unchanged. An oversized saved configuration fails loading with an explicit message and retains its frame files and manifest; category additions are blocked until the user confirms a replacement sheet, so a partial update cannot overwrite the inaccessible saved configuration. No automatic deletion or truncation is used to force a set under budget.


A further diagnostic run used a temporary copy of the same optimized probe with 100 imports and a 30-second hold after the final sample, with `MallocStackLogging=1`. Retained physical footprint for imports 10–99 remained within 49.97–50.03 MiB (stack logging adds overhead). macOS `leaks` reported **0 leaks / 0 leaked bytes** with the final nine-frame set still alive. This supports bounded retention for this scenario; it does not establish the absence of every possible ownership leak.

## AppKit image-settings comparison

The standalone probe understated whole-app rendering costs. Profiling a nine-frame set with image settings visible showed full-size frame textures in Core Animation: an initial diagnostic attributed about 37 MiB to that category. Settings now use independently rasterized thumbnails of at most 128 px, prepared on workers during staging/reload. Only the current set's thumbnail dictionary is retained. The original frames, persistence, and pet animation display keep their existing resolution. Confirmation and image-error dialogs await native window sheets instead of running nested synchronous modal loops inside main-actor tasks.

Reproduce the UI comparison with:

```sh
./macos/profile-image-app.sh 3426fc4
./macos/profile-image-app.sh
```

This compiles the actual AppDelegate and Core sources with `-O` into a temporary app with its own bundle identifier, a fresh preference suite, and a temporary image directory. It generates the deterministic transparent 3072 × 3072 sheet in a separate process (677,976 bytes; SHA-256 `73f012dc8add9366d821e9603addd680047414c34d6bdcd29737c2ac438727be`). It imports the sheet ten times through the real serialized staging/commit path, holds image settings open, waits 30 seconds, closes settings, and waits another 30 seconds. Preview preparation is included; interactive preview confirmation is bypassed to keep the workload consistent. It records physical footprint and the kernel peak ledger. It does not grant Input Monitoring permission or synthesize keyboard events. That historical harness supported revisions with the async image transaction API (`3426fc4` onward). The current harness targets the unified Change Character API from #124 and is not compatible with every older revision: reproduce old measurements using the matching historical harness, not the current Swift file against incompatible sources. Changed UI workloads are not interchangeable before/after evidence; use the standalone pipeline probe for older pipeline comparisons.

Three sequential paired runs on the same Apple Silicon / macOS 27.0.1 system produced these medians (MiB):

| AppKit scenario | Peak physical footprint | Settings after 30 s | Closed settings after 30 s |
| --- | ---: | ---: | ---: |
| Before (`3426fc4`) | 193.00 | 120.13 | 120.19 |
| With settings thumbnails | 127.67 | 98.61 | 98.72 |

Peak ranges were 192.95–195.49 MiB before and 125.11–128.30 MiB after. Final footprint ranges were 120.11–122.03 MiB before and 96.72–99.50 MiB after. Later imports plateaued in each run. Raw CSV samples are not retained in the repository.

This is about a 34% peak reduction and an 18% final-footprint reduction for this UI workload. It still exceeds the **100 MB decimal** whole-app goal, especially during replacement; 98.72 MiB is about 103.5 MB. At those historical revisions, closing the settings window retained its controller/views for reuse, so it did not need to immediately return memory. The current unified character window instead releases its session on close; see the lifecycle baseline below. These measurements establish an improvement and bounded retention for the measured configuration, not a universal 100 MB guarantee or a complete typing/sleep/frozen lifecycle baseline.

## Unified character lifecycle baseline (2026-10-20)

For repeatable shared-screen staging, Apply, close and session-release checks on the current app:

```sh
WADDLY_PROFILE_CHARACTER_LIFECYCLE=1 ./macos/profile-image-app.sh
```

The opt-in mode defaults to three real Change Character model/controller cycles per process, keeping
staged and closed states for 30 seconds each and sampling `task_info` every nominal second.
Set `WADDLY_PROFILE_CHARACTER_CYCLES=10` for a longer series (positive integers only).
Each CSV also records monotonic system uptime, so sample gaps can be measured rather than inferred
from nominal state labels. A final `lifecycle-complete` sample is emitted only after every release
check succeeds; retain the wrapper's successful exit as well as that marker.

For a typical-size fixture rather than the default large-sheet exception:

```sh
WADDLY_PROFILE_CHARACTER_LIFECYCLE=1 WADDLY_PROFILE_CHARACTER_CYCLES=10 \
  WADDLY_PROFILE_IMAGE_FIXTURE="$PWD/assets/examples/nyatinte-bot-3x3.png" \
  ./macos/profile-image-app.sh
```

The optional fixture is copied into the temporary directory; the original is not modified. Its hash
is recorded. The temporary app is now ad-hoc signed and verified before either workload, with signing
metadata and the shell/probe hashes included in its sidecar. This remains a custom-entry-point,
optimized source probe, not a notarized/signed distribution app. Do not compare these new signed runs
with older unsigned runs as if signing and tooling were unchanged.
It fails on invalid staging, failed commit/close, or a controller/model still alive after the closed
hold. Normal invocation retains the earlier ten-persistence-replacements workload. New runs write
an environment sidecar with toolchain and source/fixture hashes alongside the CSV.
For a separate, memory-perturbing allocation-stack diagnostic, also set
`WADDLY_PROFILE_STACK_LOGGING=1`; this enables `MallocStackLogging=1` only in the target app, not
the compiler or fixture generator. Do not combine logged and unlogged runs into budget medians.

Three sequential runs against product source `f1a450e` confirmed all nine controller/model releases.
For the generated 3072 × 3072 large-sheet exception, median peak/final physical footprints were
169.94/123.33 MiB (about 178.19/129.32 decimal MB). Final footprint varied from 82.28 to 124.05 MiB;
RSS still rose about 9 MiB between the second and third closed snapshots. **A consistent return to
the original footprint, absence of leaks, and absence of regression have not been established.**
A separate diagnostic found stable raster accounting but growing purgeable allocation accounting;
`leaks` reported a stable, nonzero 416 allocations / 19,936 bytes with inspection restrictions.

[Full workload, raw CSVs, environment records and diagnostic reports](measurements/character-lifecycle-20261020/README.md)
are checked in. Review subsequently found that the original probe could accept a failed later
acquisition by applying the preserved old pet; these three-run records are exploratory, not proof
of nine fresh imports. The corrected guard requires no acquisition failure and a dirty, applicable
candidate. A real corrupt-replacement check now fails closed, and a corrected single normal run
completes. The [follow-up stack investigation](measurements/character-lifecycle-20261020/follow-up/README.md)
finds growth in selected GPU/IOSurface-related stacks with stable raster accounting, but does not
explain all purgeable/RSS growth or justify a product fix.

This earlier evidence uses an optimized whole-process source probe, not the signed packaged app, a historical
comparison, or full #98/#95/#124 acceptance. The typical-input budget and other lifecycle states
still need further acceptance evidence.

### Longer signed follow-up and typical fixture

[Three ten-cycle runs with raw CSVs, receipts, source/signing provenance and a reproducible analyzer](measurements/character-lifecycle-20261020/longer/README.md)
now extend the corrected probe. A compatible historical/current typical-fixture pair and a current
large-fixture run completed all 30 fresh acquisitions and session-release checks. This is one
sequential pair, not a three-run median or the original pre-store/pre-SwiftUI comparison; production
Waddly was left running and ambient activity was not controlled.

The current typical run's 300 closed samples stayed below 100 MB (maximum 96.26 MB), but its staged
whole-process kernel peak was **107.04 MB**, so the typical lifecycle peak goal is not established.
The large run's RSS rose again in cycles 8–9 after looking nearly steady in cycles 2–7, reaching
304.75 MiB at completion, even though final physical footprint fell to 68.19 MB. Footprint oscillated
within holds; the low final value must not be called a plateau or a memory fix. Attribution, the
required remaining UI states and representative packaged-app budget/regression acceptance remain
open in #98. No product cache, residency limit, or gate was changed.

## Share dialog profile (2026-10-13)

One 30-second sample used the isolated `dev.nyatinte.waddly.sharepreview` Release app, macOS 27.0.1 on arm64, and the existing nine 418 × 418 pet frames. The dialog generated the 3 × 3 PNG and a 384 × 384, five-second MP4. The poster is shown without constructing an `AVPlayerView`; the player view is created only after the user presses Play.

| State | RSS mean / peak | Physical footprint | Kernel peak |
| --- | ---: | ---: | ---: |
| Share dialog open, after generation | 88.30 / 88.31 MiB | 53.53 MB | 105.01 MB |
| 30 seconds after closing dialog | 94.98 / 95.75 MiB | 90.52 MB | 105.01 MB |

The settled open and closed samples were below 100 MB. The cumulative peak during on-demand generation exceeded the goal by about 5 MB in this single run. This is a transient measurement, not a three-run baseline; repeat the scenario before claiming the peak target is met. Raw captures are in `dist/memory/20261012T155906Z-share-open-player-deferred/` and `dist/memory/20261012T160016Z-share-closed-player-deferred/` when available locally.

## Release E2E fixes comparison (#52, 2026-10-06)

Three sequential before/after pairs compared `d810c9e` with `429f932` on the same arm64 Mac, macOS 27.0.1 (26A434), Apple Swift 6.4. Each revision used the same optimized AppDelegate probe and generated image, ten replacements, a 30-second hold with settings visible, and another 30 seconds after closing settings. Fresh preferences and image directories isolated every run. The probe now also records RSS and peak RSS through `task_info`; the application image pipeline is unchanged. These are state snapshots and kernel cumulative peaks, not interval averages.

| Median of three runs (decimal MB) | Before | After | After − before |
| --- | ---: | ---: | ---: |
| Peak physical footprint | 133.84 | 134.14 | +0.29 |
| Settings after 30 s | 103.47 | 103.88 | +0.41 |
| Closed settings after 30 s | 103.61 | 104.07 | +0.46 |
| Peak RSS | 283.41 | 283.64 | +0.23 |
| Closed settings RSS after 30 s | 218.87 | 219.84 | +0.97 |

No memory reduction was observed. After values were slightly higher in all three pairs, but this measurement alone does not identify the cause. Both revisions exceed the 100 MB physical-footprint goal. Raw CSVs and environment/tool hashes remain local under `dist/memory/pr-52-paired-20261006T105307Z/`.
