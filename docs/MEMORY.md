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

The pre-refactor warmed scenario passed `.detectLeaks()` (via `.timed(detectLeaks: true)`). With eagerly decoded, independently owned frames, repeated evaluations reported 13 net allocator blocks / 2,840 bytes even after complete warmup, while later import iterations remained stable and the process probe returned to a fixed plateau. This process-wide framework/runtime noise makes the strict zero-growth trait unsuitable as a default CI gate for the new path. The normal suite keeps the bounded allocation guard; diagnose suspected ownership leaks with `leaks` and Instruments rather than treating a small block delta as proof. VM-backed ImageIO/CoreGraphics buffers can also escape malloc statistics, so the process workflow remains essential.

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

Raw samples from one pair: [before](memory-baselines/image-pipeline-before.csv) and [after](memory-baselines/image-pipeline-after.csv). Units in the CSV are bytes; the table rounds to MiB. Both use the deterministic generated PNG, not user images.

The new path thumbnails the preview to 480 px, directly encodes CGImage as PNG, eagerly decodes on workers, and owns each extracted frame independently. Independent buffers prevent a remaining cropped frame from retaining the complete original sheet. Atomic writes are staged and rolled back on failure; the main actor commits the new manifest before workers remove obsolete files. Reorders and removals reuse persisted filenames, and individual imports reuse their optimized PNG bytes. A main-actor queue serializes entire transactions, including worker waits and the manifest commit.

Production image sets are limited to an estimated **40 MiB**, computed from each independently decoded frame's row stride × height plus **128 KiB per frame** reserved for image wrappers and view/codec metadata. The fixed per-frame allowance also bounds the number of tiny images (at most 319); it rounds up the approximately 0.95 MB warmed allocator overhead divided across the nine-frame sample. Pixel buffers use their actual depth and stride, including 16-bit PNGs, rather than assuming four bytes per pixel.

The nine-frame 1024 × 1024 RGBA8 case occupies about 37.1 MiB under this policy. A 40 MiB resident set, about 36 MiB for a replacement sheet, a sub-MiB preview, and the historical 12–13 MB app baseline leave room within the representative 100 MB footprint goal; the standalone probe's measured peak was about 89 MiB. This is a measured design target rather than a universal guarantee for every OS/framework configuration. Existing PNG file-size, transparency, source-dimension validation, category ordering, and animation timing remain intact.

Budget checks run on worker snapshots before committing. An excessive addition leaves the current manifest and images unchanged. An oversized saved configuration fails loading with an explicit message and retains its files/manifest; category additions are blocked until the user confirms a replacement sheet, so a partial update cannot overwrite the inaccessible saved configuration. No automatic deletion or truncation is used to force a set under budget.
