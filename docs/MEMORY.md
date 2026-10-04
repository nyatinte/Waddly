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

The serialized suite generates a transparent 3072 × 3072 PNG outside the measured region, warms ImageIO/AppKit, and repeatedly imports all nine frames, encodes them, atomically overwrites temporary files, and reloads them. Autorelease pools drain between image-set replacements; tests use a temporary directory and never touch app preferences or user images.

`@Test(.trackPeakMemory(limit: 2_000_000))` runs ten iterations, with two imports per iteration. In the pinned implementation, this trait samples after each iteration: it guards retained allocator growth, not every temporary allocation. An additional `PeakMemoryTracker` samples while decoded frames and reloaded images are still alive and enforces the same 2 MB live-byte-delta budget. VM-backed ImageIO/CoreGraphics buffers may not be counted by malloc statistics, so the Release process workflow remains essential.

Leak detection is enabled in a separate serialized test using `.timed(iterations: 3, detectLeaks: true)`. This is the implementation underlying `.detectLeaks()`; a single configured trait avoids conflicting iteration settings when several performance traits are combined. It passed the warmed, deterministic image scenario locally. It measures process-wide allocator block growth and can include framework/runtime caches. Reproduce any failure with the isolated command and `leaks` before treating it as an ownership bug.

## Baseline and budgets

Baseline collected on 2026-10-04, Apple Silicon, macOS 27.0.1 (26A434), Release optimization, production source at `64729d8`:

| Measurement | Result | Limit / interpretation |
| --- | --- | --- |
| Sampled image pipeline allocator delta, images alive | 935,536–935,600 bytes | 2,000,000 bytes: a little over 2× measured baseline, allowing framework/runtime variation |
| Warmed leak scenario (three iterations) | Passed; reported end-of-iteration peak 0 bytes | No positive net allocator block growth |
| Earlier Release app startup/idle measurements (macOS 27.0) | RSS 52,176–52,416 KiB (about 51 MiB); physical footprint about 12–13 MB | Historical context only; typing/heavy/long-running states were not measured then |

The 2 MB guard is an incremental allocator budget, **not** a 2 MB total-app or image-pixel budget. The app goal remains under 100 MB physical footprint. Full lifecycle process baselines must be collected with the workflow above before changing the image residency policy or claiming before/after peak-memory savings.
