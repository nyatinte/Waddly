# Queried volatile ledger follow-up — 2026-10-21

For #98. **Diagnostic evidence, not an allocation owner, product fix, plateau, or budget acceptance.**

## Query contract and controls

`TASK_VM_INFO` does not query the three `purgeable_volatile_{pmap,resident,virtual}` map fields,
but **does** query the distinct `ledger_purgeable_volatile` balance. The existing app probe now
appends that ledger balance to its CSV. It still makes **one `TASK_VM_INFO` call per sample**;
no new query flavor, map scan, cache purge, residency policy, or product change is introduced.
The returned integer count must cover the last emitted struct field; short replies fail closed.
Device placeholders remain omitted. Older raw volatile-map placeholders remain unavailable.

A new independent `Tools/probe_task_vm_purgeable.swift` calibrates that distinction using only
its own 16 MiB purgeable allocation, committing every page, marking it volatile, restoring it to
nonvolatile, and deallocating it. It does not launch Waddly, inspect other processes, request
permissions, or force any purge. This positive control completed with exit 0 and the explicit
`QUERY_CONTRACT_COMPLETED owned_bytes=16777216` marker:

| At the owned volatile state | Basic `TASK_VM_INFO` | `TASK_VM_INFO_PURGEABLE` |
| --- | ---: | ---: |
| volatile map pmap bytes | 0 (unqueried placeholder) | 16,777,216 |
| volatile map resident bytes | 0 (unqueried placeholder) | 16,777,216 |
| volatile map virtual bytes | 0 (unqueried placeholder) | 16,777,216 |
| volatile ledger balance bytes | 16,777,216 | 16,777,216 |

Restoring the allocation returned the queried map counters to zero. Its resident pages remained
present while making it volatile reduced charged footprint by exactly 16 MiB in this control.
This demonstrates the mechanism for **that known allocation**, not the owner or cause in Waddly.

The retained negative fixture changes only the intended map-query call to the basic flavor
(`native-negative.patch`). It actually exited **1** with `controlMismatch("volatile positive control
not fully observed")` and no completion marker, even though the ledger still reports the owned
allocation. The guard therefore rejects mistaking basic-flavor map placeholders for measurements.
Raw positive/negative CSVs, outputs, statuses, source/binary hashes and environment are retained.

API evidence: [public macOS 14 XNU task_info implementation](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/osfmk/kern/task.c#L5763-L5877)
and the installed SDK's `mach/task_info.h`. The tagged source is not asserted to be the exact
installed macOS 27 kernel. The public map-query branch assigns outputs only when its inner query
succeeds and exposes no separate inner-result flag to this client. A positive control in one
process does not make every unrelated future zero an absence verdict. The app run below does
not request those map fields at all; the added ledger balance is a different accounting metric.

To run the standalone positive control:

```sh
swiftc -O -swift-version 6 -parse-as-library Tools/probe_task_vm_purgeable.swift \
  -o /tmp/waddly-volatile-contract
/tmp/waddly-volatile-contract > /tmp/waddly-volatile-contract.csv
```

An under-observed/changed contract fails rather than producing a success marker; do not rerun a
failed diagnostic until green or present it as a product-test pass.

## Ten-cycle app process

- Harness `6047b95192c001388389c07eace29ab74cb52744`; application source unchanged from main
  `fe96b61` (#150). The older `late-vm` process predates #150: two app source files differ (menu
  validation/localization accessors), reported by the analyzer. This is **not a matched historical pair**.
- Existing signed optimized source probe, generated large-sheet exception: 3072 × 3072,
  nine 1024 px frames, fixture SHA-256
  `73f012dc8add9366d821e9603addd680047414c34d6bdcd29737c2ac438727be`.
- Ten fresh acquisitions, actual staged/Apply/close paths, 30-second staged and closed holds,
  all weak controller/model release guards, **602 ordered samples**, exit 0 and `lifecycle-complete`.
  620.50 seconds between first/final samples; maximum gap 1.39 seconds.
- No vmmap/leaks/stack logging. Production Waddly was left running; ambient activity is uncontrolled.
  Isolated preferences/images and temporary source bundle were cleaned by the existing wrapper.
- A sandbox-extension warning appears in the retained output. It is not suppressed or classified
  as a product crash/root cause: all acquisition/commit/close/release checks and completion passed.

Closed-30s endpoints, **MiB** (not decimal MB):

| Cycle | Footprint | RSS | Internal | Volatile ledger |
| --- | ---: | ---: | ---: | ---: |
| 0 | 123.13 | 198.75 | 120.50 | 44.66 |
| 1 | 124.14 | 211.91 | 129.70 | 53.12 |
| 2 | 80.30 | 228.64 | 146.36 | 70.89 |
| 3 | 124.55 | 228.70 | 146.41 | 69.12 |
| 4 | 124.67 | 223.33 | 140.95 | 68.66 |
| 5 | 108.60 | 258.94 | 176.52 | 122.11 |
| 6 | 109.47 | 307.58 | 225.11 | 169.86 |
| 7 | 110.03 | 356.42 | 274.33 | 221.61 |
| 8 | 111.52 | 324.67 | 242.30 | 188.09 |
| 9 | 109.67 | 324.73 | 242.22 | 189.86 |

The ledger balance grows alongside much of the RSS/internal rise, then falls at cycle 8. It does
**not** equal the RSS increase: cycle 0→7 RSS rises 165,330,944 bytes while the ledger rises
185,548,800 bytes. No partition, subtraction-based adjusted RSS, allocation ownership, harmless
cache, original late-cycle explanation, or no-leak verdict follows. Compressed memory is also
nonzero in this process (maximum 3.05 MiB); the older run's measured zeros are not generalized.

Kernel cumulative peak footprint is **186.93 decimal MB / 178.27 MiB**, final **115.00 MB / 109.67
MiB**. Maximum sampled footprint is lower, 175.41 MB: one-second snapshots do not capture every
transient. Peak RSS is 441.19 MiB, maximum sampled RSS 440.72 MiB. This large-fixture diagnostic
is not a new typical-fixture budget or a replacement for the still-outstanding typical peak finding.

## Reproduction and remaining scope

```sh
WADDLY_PROFILE_CHARACTER_LIFECYCLE=1 WADDLY_PROFILE_CHARACTER_CYCLES=10 \
  ./macos/profile-image-app.sh
python3 docs/measurements/character-lifecycle-20261020/volatile-ledger/analyze.py
```

`analyze.py` validates sample order/schema, completion/status, signing/flavor/fixture receipts,
monotonic times, source changes, and native controls, then reproduces `summary.json`. The separate
unchanged default-workload smoke completed **23 samples / 11 columns**, exit 0, using a copied
typical fixture; it is a schema/workload check, not lifecycle or representative budget evidence.
The full `mise run check` also passed: **244 tests / 26 suites**, one existing known issue, signed
arm64 Release build. The standalone probes supplement, not replace, full validation.

Identified allocation owners/stacks, volatile map resident/virtual measurements in Waddly,
required remaining UI states, repeated medians, matched architectural comparisons and packaged-app
acceptance remain open. No product memory fix or release action is proposed; #98 stays open.
