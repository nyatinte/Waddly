#!/usr/bin/env python3
"""Check the diagnostic receipts and extract selected rounded vmmap columns."""
import csv
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
with (ROOT / "probe.csv").open(newline="") as source:
    rows = list(csv.DictReader(source))
expected = ["launch"]
for cycle in range(10):
    for phase in ("staged", "closed"):
        expected += [f"cycle-{cycle}-{phase}-{second}s" for second in range(1, 31)]
expected += ["lifecycle-complete"]
assert [row["state"] for row in rows] == expected
status = (ROOT / "inspection-status.txt").read_text()
assert "probe_wrapper_exit_code=0\n" in status and "lifecycle-complete," in status
pid = re.search(r"^target_pid=(\d+)$", status, re.MULTILINE).group(1)
environment = (ROOT / "probe.environment.txt").read_text()
assert "Signature=adhoc\n" in environment and "target_stack_logging=0\n" in environment
assert "73f012dc8add9366d821e9603addd680047414c34d6bdcd29737c2ac438727be " in environment
times = [float(row["system_uptime_seconds"]) for row in rows]
gaps = [right - left for left, right in zip(times, times[1:])]
assert min(gaps) > 0
summary = {
    "samples": len(rows),
    "elapsed_seconds": times[-1] - times[0],
    "maximum_sample_gap_seconds": max(gaps),
    "final_physical_footprint_bytes": int(rows[-1]["physical_footprint_bytes"]),
    "final_rss_bytes": int(rows[-1]["rss_bytes"]),
    "inspections": {},
}
for cycle in (0, 2, 7, 9):
    receipt = (ROOT / f"cycle-{cycle}.inspection.txt").read_text()
    assert f"command=vmmap -summary {pid}\n" in receipt
    assert "vmmap_exit_code=0\n" in receipt
    for bound in ("before", "after"):
        state = re.search(rf"^csv_{bound}=([^,]+),", receipt, re.MULTILINE).group(1)
        assert state in (f"cycle-{cycle}-closed-20s", f"cycle-{cycle}-closed-21s")
    text = (ROOT / f"cycle-{cycle}.vmmap.txt").read_text()
    assert f"WaddlyMemoryProbe [{pid}]" in text
    regions = {}
    for name in ("CG Raster Data", "CoreAnimation", "IOAccelerator (graphics)", "IOSurface", "owned unmapped"):
        values = re.search(rf"^{re.escape(name)}\s{{2,}}(.+)$", text, re.MULTILINE).group(1).split()
        regions[name] = {
            "virtual": values[0], "resident": values[1], "dirty": values[2], "regions": int(values[7])
        }
    values = re.search(r"^DefaultPurgeableMallocZone_0x[0-9a-f]+\s+(.+)$", text, re.MULTILINE).group(1).split()
    summary["inspections"][str(cycle)] = {
        "regions": regions,
        "purgeable_zone": {"resident": values[1], "allocated": values[5], "allocations": int(values[4])},
    }
with (ROOT / "counters.csv").open(newline="") as source:
    counters = list(csv.DictReader(source))
assert [row["state"] for row in counters] == expected
counter_status = (ROOT / "counters.status.txt").read_text()
assert counter_status.startswith("probe_wrapper_exit_code=0\n") and "lifecycle-complete," in counter_status
counter_environment = (ROOT / "counters.environment.txt").read_text()
assert "Signature=adhoc\n" in counter_environment and "target_stack_logging=0\n" in counter_environment
assert "73f012dc8add9366d821e9603addd680047414c34d6bdcd29737c2ac438727be " in counter_environment
source_pattern = r"^([0-9a-f]{64})  (Sources/.+\.swift)$"
assert re.findall(source_pattern, environment, re.MULTILINE)
assert re.findall(source_pattern, environment, re.MULTILINE) == re.findall(source_pattern, counter_environment, re.MULTILINE)
# An observation of these retained samples, not a portable API identity or adjusted-RSS budget.
assert all(int(row["rss_bytes"]) == sum(int(row[key]) for key in
           ("internal_bytes", "external_bytes", "reusable_bytes")) for row in counters)
# TASK_VM_INFO does not query the volatile fields; public XNU also hardcodes device to zero.
# Preserve the raw CSV placeholders, but never group them with actually queried zero counters.
unavailable_fields = ("purgeable_volatile_resident_bytes", "purgeable_volatile_virtual_bytes", "device_bytes")
measured_zero_fields = ("compressed_bytes",)
assert all(int(row[key]) == 0 for row in counters for key in measured_zero_fields)
counter_times = [float(row["system_uptime_seconds"]) for row in counters]
counter_gaps = [right - left for left, right in zip(counter_times, counter_times[1:])]
assert min(counter_gaps) > 0
endpoint_fields = ("physical_footprint_bytes", "rss_bytes", "internal_bytes", "external_bytes", "reusable_bytes")
summary["counter_run"] = {
    "samples": len(counters),
    "elapsed_seconds": counter_times[-1] - counter_times[0],
    "maximum_sample_gap_seconds": max(counter_gaps),
    "task_info_flavor": "TASK_VM_INFO",
    "unavailable_fields_for_selected_flavor": list(unavailable_fields),
    "measured_zero_fields_in_all_samples": list(measured_zero_fields),
    "observed_rss_identity_in_all_samples": "internal_bytes + external_bytes + reusable_bytes",
    "closed_30s_endpoints": [
        {"state": row["state"], **{key: int(row[key]) for key in endpoint_fields}}
        for row in counters if "-closed-30s" in row["state"]
    ],
}
print(json.dumps(summary, indent=2, sort_keys=True))
