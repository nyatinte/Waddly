#!/usr/bin/env python3
"""Validate retained receipts; report raw byte metrics without an adjusted RSS."""
import csv
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
FIELDS = ["state", "physical_footprint_bytes", "peak_physical_footprint_bytes", "rss_bytes",
          "peak_rss_bytes", "system_uptime_seconds", "reusable_bytes", "compressed_bytes",
          "internal_bytes", "external_bytes", "ledger_purgeable_volatile_bytes"]


def load(name):
    with (ROOT / name).open(newline="") as source:
        return list(csv.DictReader(source))


def source_hashes(text):
    return dict((path, digest) for digest, path in
                re.findall(r"^([0-9a-f]{64})  (Sources/.+\.swift)$", text, re.MULTILINE))


rows = load("probe.csv")
expected = ["launch"] + [f"cycle-{cycle}-{phase}-{second}s" for cycle in range(10)
                         for phase in ("staged", "closed") for second in range(1, 31)] + ["lifecycle-complete"]
assert [r["state"] for r in rows] == expected
assert all(list(r) == FIELDS and all(v is not None for v in r.values()) for r in rows)
assert (ROOT / "probe.status.txt").read_text() == "exit_status=0\n"
environment = (ROOT / "probe.environment.txt").read_text()
for marker in ("character_cycles=10\n", "task_info_flavor=TASK_VM_INFO\n", "Signature=adhoc\n",
               "task_info_volatile_metric=ledger_purgeable_volatile\n", "target_stack_logging=0\n",
               "73f012dc8add9366d821e9603addd680047414c34d6bdcd29737c2ac438727be "):
    assert marker in environment
assert source_hashes(environment)
times = [float(r["system_uptime_seconds"]) for r in rows]
gaps = [b - a for a, b in zip(times, times[1:])]
assert min(gaps) > 0
metrics = [key for key in FIELDS if key not in ("state", "system_uptime_seconds")]
summary = {
    "samples": len(rows), "columns": len(FIELDS), "elapsed_seconds": times[-1] - times[0],
    "maximum_sample_gap_seconds": max(gaps), "task_info_flavor": "TASK_VM_INFO",
    "maxima_bytes": {key: max(int(r[key]) for r in rows) for key in metrics},
    "final_bytes": {key: int(rows[-1][key]) for key in metrics},
    "closed_30s_endpoints": [{"state": r["state"], **{key: int(r[key]) for key in metrics}}
                             for r in rows if r["state"].endswith("-closed-30s")],
}
previous = source_hashes((ROOT.parent / "late-vm/counters.environment.txt").read_text())
current = source_hashes(environment)
summary["changed_application_source_paths_vs_previous_counters"] = sorted(
    path for path in previous.keys() | current.keys() if previous.get(path) != current.get(path))
default = load("default.csv")
default_states = ["launch"] + [state for i in range(10) for state in (f"prepared-{i}", f"import-{i}")]
default_states += ["character-import-30s", "return-idle-30s"]
assert [r["state"] for r in default] == default_states
assert all(list(r) == FIELDS for r in default)
assert (ROOT / "default.status.txt").read_text() == "exit_status=0\n"
assert source_hashes((ROOT / "default.environment.txt").read_text()) == current
summary["default_workload_contract_smoke"] = {"samples": len(default), "columns": len(FIELDS)}

positive = load("native-positive.csv")
negative = load("native-negative.csv")
assert len(positive) == 9 and len(negative) == 6
assert (ROOT / "native-positive.status.txt").read_text() == "exit_status=0\n"
assert "QUERY_CONTRACT_COMPLETED owned_bytes=16777216\n" in (ROOT / "native-positive.output.txt").read_text()
assert (ROOT / "native-negative.status.txt").read_text() == "exit_status=1\n"
negative_output = (ROOT / "native-negative.output.txt").read_text()
assert 'controlMismatch("volatile positive control not fully observed")' in negative_output
assert "QUERY_CONTRACT_COMPLETED" not in negative_output
volatile = [r for r in positive if r["stage"] == "volatile"]
assert [r["flavor"] for r in volatile] == ["TASK_VM_INFO", "TASK_VM_INFO_PURGEABLE"]
map_fields = ["purgeable_volatile_pmap_bytes", "purgeable_volatile_resident_bytes",
              "purgeable_volatile_virtual_bytes"]
assert all(int(volatile[0][key]) == 0 for key in map_fields)  # Deliberately exposed placeholders.
assert all(int(volatile[1][key]) >= 16777216 for key in map_fields)
assert all(int(r["ledger_purgeable_volatile_bytes"]) >= 16777216 for r in volatile)
restored = next(r for r in positive if r["stage"] == "restored")
assert all(int(restored[key]) == 0 for key in map_fields)
summary["native_query_positive_control"] = {
    "owned_bytes": 16777216, "volatile_rows": volatile,
    "basic_flavor_unavailable_map_fields": map_fields,
    "queried_ledger_field_for_both_flavors": "ledger_purgeable_volatile_bytes",
}
summary["native_wrong_flavor_negative_control"] = {"exit_status": 1, "samples": len(negative)}
print(json.dumps(summary, indent=2, sort_keys=True))
