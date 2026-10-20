# Acquisition-guard correction and stack investigation

## Review correction

Pullfrog found a real false-success path in the original probe at `d433a98`: when reopening a
committed pet, a failed acquisition preserves that pet, so `canApply` remains true. Applying the
old pet then clears the acquisition error. The original three-run CSVs remain immutable exploratory
data, **not proof that all intended replacement acquisitions succeeded**. Their weak-reference
checks still observed controller/model release, but cannot strengthen that acquisition guarantee.

The probe now requires all three conditions immediately after `stageFiles`, before measuring the
staged hold: `failure == nil`, `isDirty`, and `canApply`. The new model regression test documents
that a loaded pet remains applicable but clean after an unreadable replacement, which is why
`canApply` alone is insufficient. This preserves the product's intentional recovery behavior.

### Actual negative probe check

The full optimized probe was started with its normal generated fixture. After the first Apply and
the first closed sample, the **generated temporary** `source.png` was replaced with invalid bytes.
The source path was obtained from the probe process arguments and checked to belong to that probe's
temporary directory. No repository fixture or user file was modified.

Result: process exit **1**, `Image app probe failed: invalidCandidate`; `negative.csv` has exactly
61 samples (launch + cycle 0's two holds), and no cycle 1 staged hold. `negative-status.txt` records
the exit and original CSV name. This exercises the corrected guard in the actual probe rather than
only retesting the model. The environment sidecar's fixture hash was captured **before** corruption.

## Corrected uninstrumented run

`corrected.csv` records one normal run with the stronger guard: 181 ordered samples and three
successful fresh imports, commits, closes and weak controller/model release checks. The generated
large-sheet fixture, product sources, compiler options and 30-second holds are unchanged. The new
probe hash and toolchain/product file hashes are recorded in `corrected.environment.txt`.

| Corrected single run, MiB | Cycle 0 | Cycle 1 | Cycle 2 |
| --- | ---: | ---: | ---: |
| Closed after 30 seconds: physical footprint | 121.16 | 121.89 | 123.52 |
| Closed after 30 seconds: RSS | 195.19 | 206.16 | 216.09 |

Kernel peak physical footprint: **168.91 MiB**. This is one corrected run, not a replacement
three-run median or proof of bounded retention. It still does not consistently return to its first
closed state. The old medians are not upgraded to stronger-guard acceptance retrospectively.

## Allocation-stack diagnostic (separate, perturbed workload)

```sh
WADDLY_PROFILE_CHARACTER_LIFECYCLE=1 WADDLY_PROFILE_STACK_LOGGING=1 ./macos/profile-image-app.sh
# During closed holds of cycles 0 and 2, on the same probe PID:
malloc_history PID -allBySize -fullStacks
vmmap -summary PID
```

Only the target executable receives `MallocStackLogging=1`; the compiler and fixture generator do
not. `stack-logging.csv` and its environment sidecar record this separate process (PID 80029).
`stack-status.txt` records successful inspection exits. All three corrected acquisition/commit/
close/release checks passed. Logging and inspection materially perturb memory: the logged peak/final
physical footprints were 232.33/190.81 MiB, and `vmmap` records Performance Tool Data. **Do not use
these numbers as the uninstrumented budget, or directly subtract them from the baseline.**

### What the recorded stacks show

The live-allocation reports contain large file mappings as well as heap/VM allocations; reported
allocation byte totals are **not RSS or physical footprint**. Examples and normalized differences
are retained, not an asserted accounting of the entire process:

| Recorded stack aggregate | After cycle 0 | After cycle 2 |
| --- | ---: | ---: |
| `mmap → create_protected_copy → CGBitmapContextCreateImage → PetSpriteSheetImporter.cells → CharacterSheetLoader.load` | 27 calls / 37,896,192 bytes | 27 calls / 37,896,192 bytes |
| `IOGPUResourceCreate → …CommandBufferStorageAllocResourceAtIndex → …newCommand → …beginRenderPass → QuartzCore` | 1,556,480 bytes | 3,112,960 bytes |
| `IOGPUResourceCreate → …initializeOnDemandDataBufferSlow → …beginRenderPass → QuartzCore` | 786,432 bytes | 1,572,864 bytes |
| `IOSurfaceClientCreateChild → IOSurfaceCreate → …CABackingStorePrepareUpdates_ → …CALayer display` (this normalized stack) | absent | 1,851,392 bytes |

Both `vmmap` captures still show CG Raster Data at 36.8M / 36 regions. The purgeable zone's bytes
allocated increase from 45.0M to 61.6M, as in the earlier unlogged diagnostic. Growth visible in
these selected stacks points toward **rendering resources/pools as an investigation target**, not
accumulating complete imported-frame sets. It does **not** explain all purgeable or RSS growth,
establish a harmless cache ceiling, or prove the absence of other ownership leaks. No product
code or cache policy was changed based on this diagnostic.

### Artifact selection and reproducibility limits

The complete stack reports are about 232/231 MB locally under `dist/memory/lifecycle-stacks/`, so
they are not committed. `cycle-{0,2}-stack-excerpts.txt` include their byte lengths/SHA-256, command,
and complete original backtraces for selected blocks: size at least 32,768 bytes and containing the
raster aggregate above, `IOSurfaceClientCreateChild`, `IOGPUResourceCreate`, or
`PetSpriteSheetImporter.thumbnails`. These are explicitly **excerpts**, not full or exhaustive raw
reports. `cycle-{0,2}-vmmap.txt` are complete summary reports.

`large-stack-deltas.txt` is derived: only blocks at least 32,768 bytes are grouped by full frame
symbol sequence after dropping leading frame numbers, frame addresses and trailing instruction
offsets; the 30 largest positive endpoint differences are retained (fewer if fewer grow). This can
merge sites within a symbol and excludes small blocks; it is not a complete growth reconciliation.
Unknown frames remain unsymbolicated. The huge stable Metal/theme file mappings must not be called
resident leaks merely because `malloc_history` lists their virtual allocation sizes.

Validation of this follow-up: the focused model regression completed (1 test / 1 suite), the actual
negative probe rejected the failed second acquisition, and the corrected normal/logged probes
completed. The signed Release build passed. The full local `mise run test` again failed closed on
an unfinished App run during `SetupWizardCharacterImportTests`; focused coverage is **not** a full
pass. Next useful evidence is a longer corrected uninstrumented cycle series or direct attribution
of purgeable allocations before proposing a cache/ownership fix. #98/#95/#124 remain open.
