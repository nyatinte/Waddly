# Longer signed lifecycle measurements (#98)

## Scope and controls

Three sequential, uninstrumented ten-cycle processes completed on 2026-10-20, with the same
`-O -swift-version 6` probe, ad-hoc signing/verification, bundle identifier, fresh UUID preferences,
temporary image directories, and nominal 30-second staged/closed holds. Each acquisition required
`failure == nil`, `isDirty`, and `canApply`; each Apply/close and weak controller/model release check
passed. Each CSV has 602 samples: launch + 10 × (30 staged + 30 closed) + `lifecycle-complete`.
All three wrappers exited 0. No stack logging, memory-pressure injection, cache clearing, permission
grant or synthetic keyboard input was used.

- Harness/current source: `182fcd381524f65ee4f5ec918201a823ced7ab96` (application code is unchanged
  from `a160bf4`; this commit changes the profiling tool and its documentation).
- Compatible historical product source: `f0234f79cff31bd4c1e8212bc9bc07c4443c676a`, before the #124
  accessibility follow-up and #146. It is **already after** the original store extraction and SwiftUI
  migration, so this pair cannot establish their original before/after acceptance.
- Typical fixture: repository `assets/examples/nyatinte-bot-3x3.png`, 768 × 768, nine 256 × 256 frames,
  477,743 bytes; SHA-256 `32ed8d6e9a285fd6da61d4b93bcd532f072e05bf417096a69f7ee3fcbe793c8d`.
- Large fixture: generated transparent 3072 × 3072, nine 1024 × 1024 frames, 677,976 bytes;
  SHA-256 `73f012dc8add9366d821e9603addd680047414c34d6bdcd29737c2ac438727be`.
- Host: Apple Silicon, macOS 27.0.1 (`26A434`), Swift 6.4. Sidecars retain exact source, harness,
  shell, fixture, toolchain, and signing provenance. The sidecar's first Git SHA is the harness
  checkout; `baseline_revision` and the source hashes identify the archived product being compiled.
- Production Waddly PID 35688 was running and deliberately left untouched. Ambient user activity
  and system load were **not controlled**. Before/after system-memory queries are retained; reported
  free percentage was 53–56%. These are not continuous pressure measurements or proof of no pressure.
- These are custom-entry-point, optimized, ad-hoc-signed source apps, **not** the packaged/notarized
  distribution app. Do not merge these results into older unsigned/stack-logged medians.

## Results

Physical footprint is charged process memory, not RSS. MiB is 1,048,576 bytes; the app goal is
**100,000,000 bytes**, not 100 MiB. Final values are completion-marker snapshots, not hold averages.

| Process (one each, in this order) | Elapsed s | Kernel peak footprint MiB / MB | Final footprint MiB / MB | Final RSS MiB |
| --- | ---: | ---: | ---: | ---: |
| Historical / typical | 632.35 | 101.08 / 105.99 | 87.06 / 91.29 | 130.77 |
| Current / typical | 620.53 | 102.08 / 107.04 | 86.84 / 91.06 | 129.20 |
| Current / large | 629.78 | 175.44 / 183.96 | 65.03 / 68.19 | 304.75 |

The maximum gap between adjacent samples was 1.261 / 1.198 / 1.473 seconds respectively. Recorded
monotonic times, not the nominal labels, determine elapsed duration. Kernel peak ledgers include
transients missed between samples.

### Closed after 30 nominal seconds, MiB

| Cycle | Historical typical footprint / RSS | Current typical footprint / RSS | Current large footprint / RSS |
| --- | ---: | ---: | ---: |
| 0 | 42.39 / 119.39 | 86.63 / 119.30 | 121.47 / 197.03 |
| 1 | 87.31 / 122.92 | 42.83 / 123.34 | 78.91 / 209.14 |
| 2 | 88.58 / 125.55 | 42.77 / 123.97 | 124.14 / 217.81 |
| 3 | 87.63 / 128.34 | 86.16 / 124.56 | 124.11 / 217.83 |
| 4 | 88.84 / 131.28 | 85.89 / 124.33 | 124.08 / 217.83 |
| 5 | 85.66 / 129.45 | 89.83 / 122.78 | 121.45 / 217.89 |
| 6 | 87.41 / 130.44 | 88.81 / 124.84 | 121.45 / 217.89 |
| 7 | 87.09 / 130.80 | 88.95 / 128.05 | 121.50 / 218.00 |
| 8 | 42.83 / 130.81 | 86.99 / 129.88 | 106.35 / 257.81 |
| 9 | 87.06 / 130.77 | 86.84 / 129.20 | 65.14 / 304.75 |

**Do not call a low endpoint a plateau.** The final closed hold's footprint min / mean / max was:

- Historical typical: 42.81 / 58.91 / 87.36 MiB.
- Current typical: 42.56 / 58.98 / 87.06 MiB.
- Current large: 64.78 / 85.84 / 117.25 MiB. Its final-hold RSS was 304.75–318.45 MiB;
  the kernel RSS peak over the whole run was 374.83 MiB.

The footprint repeatedly moved between low/high values while RSS could stay high. This observation
is **not an attribution** to purgeability, compression, GPU caches, or ownership leaks. The earlier
three-cycle stack excerpts cannot be used to explain this new late-run behavior retroactively.

## Acceptance decision

- **Longer corrected run: measured.** All 30 fresh acquisitions/commits/closes and session-release
  checks passed; all ordered samples, actual times and completion receipts are retained.
- **Typical closed-state goal: observed only in this fixture/run pair.** All 300 closed samples in
  the current typical run were at most 96.26 MB (historical: 97.45 MB), below 100 MB. This does not
  cover Setup, the advanced editor, all supported inputs, typing, or the packaged app.
- **Typical lifecycle peak goal: not met by this measured process.** The current kernel peak was
  107.04 MB, first reached on `cycle-6-staged-30s`; it is not covered by the large-sheet exception.
  This is a whole-process staged-window peak, not an independently measured image-pipeline peak.
- **Historical comparison: limited evidence, not a no-regression verdict.** The current typical
  kernel peak was 1.05 MB higher and final footprint 0.23 MB lower. One sequential pair, different
  elapsed durations and uncontrolled ambient activity are insufficient for significance, attribution,
  three-run medians, or original pre-store/pre-SwiftUI acceptance. The original pre-store revision
  `e7a026d` has no `CharacterImportWindowController`; this same unified-screen workload cannot compile
  unchanged against it. No substitute UI path is presented as equivalent.
- **Large retention/plateau: unresolved.** RSS looked nearly steady during cycles 2–7, then grew
  substantially in cycles 8–9 while footprint fell. A three-cycle result would miss this late growth.
  Neither a universal plateau nor an actual image/view leak is established. Next useful work is
  bounded VM/allocation attribution around those later phases in a separately identified process;
  do not add speculative cache clearing or waive a budget based on the final 68.19 MB snapshot.

**#98 stays open.** Required Setup/advanced-editor states, matched original architectural comparisons,
representative distribution-app budgets, repeated comparisons and residual allocation attribution
remain outstanding. No product memory policy or gate was changed.

## Reproduction and validation

```sh
# Use the same updated harness for both archived product sources, sequentially.
WADDLY_PROFILE_CHARACTER_LIFECYCLE=1 WADDLY_PROFILE_CHARACTER_CYCLES=10 \
  WADDLY_PROFILE_IMAGE_FIXTURE="$PWD/assets/examples/nyatinte-bot-3x3.png" \
  ./macos/profile-image-app.sh f0234f79cff31bd4c1e8212bc9bc07c4443c676a
WADDLY_PROFILE_CHARACTER_LIFECYCLE=1 WADDLY_PROFILE_CHARACTER_CYCLES=10 \
  WADDLY_PROFILE_IMAGE_FIXTURE="$PWD/assets/examples/nyatinte-bot-3x3.png" \
  ./macos/profile-image-app.sh 182fcd381524f65ee4f5ec918201a823ced7ab96
WADDLY_PROFILE_CHARACTER_LIFECYCLE=1 WADDLY_PROFILE_CHARACTER_CYCLES=10 \
  ./macos/profile-image-app.sh 182fcd381524f65ee4f5ec918201a823ced7ab96

python3 docs/measurements/character-lifecycle-20261020/longer/analyze.py > /tmp/lifecycle-summary.json && \
  diff -u docs/measurements/character-lifecycle-20261020/longer/summary.json /tmp/lifecycle-summary.json
```

The checked-in `analyze.py` validates the full state sequence, completion/exit receipts, fixture hashes,
monotonic ordering, signing and disabled stack logging before computing `summary.json`. Files ending
in `.output.txt` preserve full wrapper output, including nonfatal platform/compiler sandbox warnings;
`.context.txt` files record the long-run boundaries, order and system-memory queries.

- `invalid-zero.*`: actual isolated lifecycle probe with cycles `0` exited 1 with
  `invalidCycleCount`, only the launch sample and no completion marker. It did not silently fall back
  to a successful shorter workload.
- `default-typical.*`: with lifecycle mode disabled, the original ten direct persistence replacements
  and two 30-second holds completed unchanged (23 samples, exit 0). Its peak/final footprint was
  48.35/37.21 MB. This is **not** the repeated staged-window workload, so it is not evidence of a
  lifecycle memory improvement and is not combined with that series.
- Full `mise run check` passed: 241 tests / 25 suites, one existing known issue, signed arm64 Release
  build and all format/lint/safety checks. An initial check stopped at an overlong CSV-header line;
  the line was split before the successful full validation. No test-selection or gate changes.
