# Repeatable memory measurements

The production goal is **less than 100 MB of physical footprint** in representative supported configurations. Record RSS as context, too: it includes shared resident pages, while macOS physical footprint accounts for the process's charged physical memory (including compressed memory). Neither equals the allocator's live-byte delta used by the regression suite. A single startup reading does not establish a budget for arbitrary numbers of user images.

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

The new path thumbnails the preview to 480 px, directly encodes CGImage as PNG, eagerly decodes on workers, and owns each extracted frame independently. Independent buffers prevent a remaining cropped frame from retaining the complete original sheet. Atomic writes are staged and rolled back on failure; the main actor commits the new manifest before workers remove obsolete files. Reorders and removals reuse persisted filenames, and individual imports reuse their optimized PNG bytes. A main-actor queue serializes entire transactions, including worker waits and the manifest commit.

Production image sets are limited to an estimated **40 MiB**, computed from each independently decoded frame's row stride × height plus **192 KiB per frame** reserved for image wrappers, view/codec metadata, and a settings thumbnail. This rounds up the approximately 0.95 MB warmed allocator overhead divided across nine frames plus at most 64 KiB for a 128 × 128 RGBA8 thumbnail. The fixed allowance bounds the number of tiny images to at most 213. Pixel buffers use their actual depth and stride, including 16-bit PNGs, rather than assuming four bytes per pixel.

The nine-frame 1024 × 1024 RGBA8 case occupies about 37.7 MiB under this policy. The standalone probe's peak was about 89 MiB, but this does **not** establish the 100 MB whole-app goal: AppKit windows, layer textures, and runtime caches add substantial memory. The policy bounds decoded frame residency, not total process footprint or replacement peaks. Existing PNG file-size, transparency, source-dimension validation, category ordering, and animation timing remain intact.

Budget checks run on worker snapshots before committing. An excessive addition leaves the current manifest and images unchanged. An oversized saved configuration fails loading with an explicit message and retains its files/manifest; category additions are blocked until the user confirms a replacement sheet, so a partial update cannot overwrite the inaccessible saved configuration. No automatic deletion or truncation is used to force a set under budget.


A further diagnostic run used a temporary copy of the same optimized probe with 100 imports and a 30-second hold after the final sample, with `MallocStackLogging=1`. Retained physical footprint for imports 10–99 remained within 49.97–50.03 MiB (stack logging adds overhead). macOS `leaks` reported **0 leaks / 0 leaked bytes** with the final nine-frame set still alive. This supports bounded retention for this scenario; it does not establish the absence of every possible ownership leak.

## AppKit image-settings comparison

The standalone probe understated whole-app rendering costs. Profiling a nine-frame set with image settings visible showed full-size frame textures in Core Animation: an initial diagnostic attributed about 37 MiB to that category. Settings now use independently rasterized thumbnails of at most 128 px, prepared on workers during staging/reload. Only the current set's thumbnail dictionary is retained. The original frames, persistence, and pet animation display keep their existing resolution. Confirmation and image-error dialogs await native window sheets instead of running nested synchronous modal loops inside main-actor tasks.

Reproduce the UI comparison with:

```sh
./macos/profile-image-app.sh 3426fc4
./macos/profile-image-app.sh
```

This compiles the actual AppDelegate and Core sources with `-O` into a temporary app with its own bundle identifier, a fresh preference suite, and a temporary image directory. It generates the deterministic transparent 3072 × 3072 sheet in a separate process (677,976 bytes; SHA-256 `73f012dc8add9366d821e9603addd680047414c34d6bdcd29737c2ac438727be`). It imports the sheet ten times through the real serialized staging/commit path, holds image settings open, waits 30 seconds, closes settings, and waits another 30 seconds. Preview preparation is included; interactive preview confirmation is bypassed to keep the workload consistent. It records physical footprint and the kernel peak ledger. It does not grant Input Monitoring permission or synthesize keyboard events. This probe supports historical revisions with the async image transaction API (`3426fc4` onward); use the standalone probe for older revisions.

Three sequential paired runs on the same Apple Silicon / macOS 27.0.1 system produced these medians (MiB):

| AppKit scenario | Peak physical footprint | Settings after 30 s | Closed settings after 30 s |
| --- | ---: | ---: | ---: |
| Before (`3426fc4`) | 193.00 | 120.13 | 120.19 |
| With settings thumbnails | 127.67 | 98.61 | 98.72 |

Peak ranges were 192.95–195.49 MiB before and 125.11–128.30 MiB after. Final footprint ranges were 120.11–122.03 MiB before and 96.72–99.50 MiB after. Later imports plateaued in each run. Raw CSV samples are not retained in the repository.

This is about a 34% peak reduction and an 18% final-footprint reduction for this UI workload. It still exceeds the **100 MB decimal** whole-app goal, especially during replacement; 98.72 MiB is about 103.5 MB. Closing the settings window retains its controller/views for reuse, so it need not immediately return memory. These measurements establish an improvement and bounded retention for the measured configuration, not a universal 100 MB guarantee or a complete typing/sleep/frozen lifecycle baseline.
