# Separate late-cycle VM and native-counter diagnostics (#98)

## Method and provenance

This follows the [uninstrumented ten-cycle series](../longer/README.md). It is **diagnostic evidence,
not another budget median, a product fix, or a retroactive explanation of that process**.

1. One ten-cycle large-fixture process used source/harness checkout
   `b11e696e2dc673ae46aed73f675226527a608f45`. `vmmap -summary` inspected the same isolated PID
   **29372** during closed holds of cycles 0, 2, 7 and 9. All inspections exited 0. Each receipt keeps
   the requested state, command, UTC bounds, and actual CSV rows before/after inspection: all stayed
   at closed-20s or closed-21s, with no phase substitution.
2. A second, uninspected ten-cycle process used
   `7934e8dbe0122d733bcac99de42551575e7c23c8`. Its CSV initially exposed seven extra `task_vm_info`
   fields, but review found three are not queried by the selected API; see the correction below.
   Its original raw CSV is preserved unchanged. It has **no external VM inspection**. Stack-logging
   variables were removed from its environment explicitly.

The analyzer verifies that both sidecars' product-source hashes match exactly. Application code,
fixture, signing and cycle protocol are unchanged; the second probe's different hash records its
extra output fields. Both are optimized, ad-hoc-signed custom-entry-point apps, not packaged Release
acceptance. Each process completed 10 fresh stage/Apply/close/weak-release checks, all 602 ordered
samples, the final marker and exit 0. The probe was not retried until a favorable outcome.

Both used the generated 3072 × 3072 fixture (nine 1024 × 1024 frames), SHA-256
`73f012dc8add9366d821e9603addd680047414c34d6bdcd29737c2ac438727be`, fresh UUID preferences and
temporary images, on Apple Silicon / macOS 27.0.1 (`26A434`) / Swift 6.4. No permission grants,
synthetic keyboard events, pressure injection, cache clearing, allocation-stack logging or product
memory-policy changes. Production Waddly PID 35688 was deliberately left untouched; ambient activity
was uncontrolled. The VM run's boundary queries reported 58% free; that is not continuous pressure
measurement. Native inspection can perturb residency and timing, so its numbers are not substituted
for the earlier uninstrumented results.

## Four VM summaries: observations, not complete attribution

The table preserves `vmmap`'s rounded **K/M display values**, not precise raw byte counters.

| Selected summary value | Cycle 0 | Cycle 2 | Cycle 7 | Cycle 9 |
| --- | ---: | ---: | ---: | ---: |
| CG Raster Data resident / regions | 36.8M / 36 | 36.8M / 36 | 36.8M / 36 | 36.8M / 36 |
| CoreAnimation resident / regions | 176K / 9 | 176K / 9 | 176K / 9 | 176K / 9 |
| IOAccelerator (graphics) resident / regions | 16K / 1 | 16K / 1 | 16K / 1 | 16K / 1 |
| IOSurface resident / regions | 1808K / 30 | 1808K / 30 | 3616K / 30 | 3616K / 30 |
| **owned unmapped resident / regions** | **288K / 15** | **1904K / 34** | **3568K / 56** | **5184K / 75** |
| DefaultPurgeableMallocZone allocated / resident | 117.2M / 304K | 217.2M / 432K | 185.4M / 368K | 185.4M / 368K |

- Stable CG Raster Data size/count does not show accumulating complete frame rasters in these four
  snapshots. It does not exclude every retained object, other image representation, or later growth.
- `owned unmapped` resident grows by 4896K and 60 regions between the first and last inspections.
  IOSurface resident also changes. **No allocation stack or owner is identified for that growth**;
  generic `owned unmapped` must not be renamed an image/GPU leak based on its name alone.
- Purgeable-zone **allocated**, virtual, resident and charged footprint are different quantities.
  In this process, the large zone-allocated change co-moves with the early RSS rise and subsequent
  reduction, but is not a byte-for-byte RSS reconciliation or proof of kernel volatility.
- `vmmap` shared-library/mapped-region totals are not the same accounting as task RSS or charged
  footprint. Do not sum this selected table into either one or compare inspected snapshots as if
  they were simultaneous with the prior uninspected run.

This process's closed-30s RSS rises early (259.89 → 311.47 → 363.80 MiB), then is approximately
331.70–332.17 MiB for cycles 3–9. Its final charged footprint is 82.33 MB. **It did not reproduce the
original cycle-8/9 timing**, does not establish a universal plateau, and does not explain the earlier
late jump. Its elapsed sample duration was 662.82 seconds; the maximum adjacent gap was 1.686 seconds.

## Raw native counters: a narrower accounting observation

### Query-contract correction from review

The retained CSV exposed seven struct fields, but `TASK_VM_INFO` only queries the added **reusable,
compressed, internal and external** counters. Public XNU initializes volatile-resident/virtual fields
to zero and queries them only for `TASK_VM_INFO_PURGEABLE`; it also hardcodes device/device-peak to
zero. Thus the three retained columns `purgeable_volatile_resident_bytes`,
`purgeable_volatile_virtual_bytes`, and `device_bytes` are **unavailable placeholders, not measured
zeros**. They cannot exclude volatile or graphics memory, even though every raw cell contains zero.

API evidence: [macOS 14 public XNU task_info implementation](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/osfmk/kern/task.c#L5763-L5814)
and the [current public source](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c)
retain this distinction. These public sources are not claimed to identify the exact installed macOS
27 kernel. The earlier interpretation of the placeholders as volatility measurements is **withdrawn**.

Future CSVs omit these three unavailable columns, and sidecars explicitly record
`task_info_flavor=TASK_VM_INFO`. The analyzer marks them unavailable for these retained runs instead
of grouping them with sampled zero counters. No query-flavor change, extra kernel call, invented
adjusted-RSS budget, or product behavior is introduced. Actual volatile measurements would require
the appropriate query and separately recorded protocol; none are claimed here.

The second process completed 602 samples over 661.43 seconds (maximum gap 1.659 seconds). Selected
closed-30s endpoints, **MiB**:

| Cycle | Footprint | RSS | Internal | External | Reusable |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0 | 73.45 | 259.98 | 190.59 | 67.14 | 2.25 |
| 2 | 72.55 | 362.86 | 290.97 | 68.81 | 3.08 |
| 7 | 73.85 | 331.11 | 258.86 | 68.81 | 3.44 |
| 9 | 74.03 | 331.33 | 259.03 | 68.81 | 3.48 |

Across **these retained 602 samples**, RSS exactly equals the reported internal + external + reusable
bytes. This is an empirical identity for this dataset/kernel, not a newly promised portable API
identity. The substantial early rise sits primarily in the **internal counter**, not in the small
reusable change or external counter. Reusable stays at most 3.52 MiB across the whole process.
The queried compressed ledger counter reports zero in every sample. Volatile-resident/virtual and
device remain **unavailable**, irrespective of their zero placeholders. An allocator zone's name is
not a kernel purgeability classification. These counters do not identify internal allocation owners.

Thus the similar early RSS ramp also occurs without VM inspection, but **neither process explains
the original late ramp**. The queried compressed counter shows no recorded increase, but **volatile memory remains unmeasured
and cannot be ruled out**. These data are not grounds to subtract RSS into an artificial passing
budget, declare all remaining memory harmless, or reinterpret the earlier run's unrecorded counters.

## Validation, artifacts and remaining work

```sh
python3 docs/measurements/character-lifecycle-20261020/late-vm/analyze.py > /tmp/late-vm-summary.json && \
  diff -u docs/measurements/character-lifecycle-20261020/late-vm/summary.json /tmp/late-vm-summary.json
```

The stdlib-only analyzer verifies both sequences, marker/exit receipts, fixture/signature/disabled
stack-logging provenance, matching product-source hashes, inspection PID/phase bounds, monotonic
sample times and the stated counter observations before generating `summary.json`. It extracts only
the selected rounded VM columns; full summaries and complete wrapper output are retained too.
`collect.sh.txt` archives the one-off collector (edit its ROOT and output directory before reuse;
use harness checkout `b11e696` to replay that original inspected protocol). The counter harness is
`7934e8d`; both versions are retained in Git and their exact hashes are in the sidecars.
For the uninspected counter run, use the current profiling wrapper with cycles 10, the generated
fixture, stack logging off and no inspection; the counter fields are always part of new CSVs.

Full `mise run check` after the Swift change passed 241 tests / 25 suites (one existing known issue),
format/lint/localization/complexity/safety/completion-guard checks and the signed arm64 Release build.
Neither diagnostic is a subset substituted for that validation.

**#98 remains open.** Next attribution targets include the growing owned-unmapped regions and
internal accounting, using appropriately identified allocation/VM diagnostics. No exact owner,
root-cause fix, original architectural no-regression comparison, full typical-input budget, all
required UI states, universal plateau or zero-leak claim is established. Keep the prior large and
typical budget findings unchanged.
