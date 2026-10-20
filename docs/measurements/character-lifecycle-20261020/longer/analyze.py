#!/usr/bin/env python3
"""Validate the ordered #98 probe receipts and summarize immutable CSVs (stdlib only)."""
import csv
import json
from pathlib import Path
from statistics import mean

ROOT = Path(__file__).resolve().parent
TYPICAL_HASH = "32ed8d6e9a285fd6da61d4b93bcd532f072e05bf417096a69f7ee3fcbe793c8d"
LARGE_HASH = "73f012dc8add9366d821e9603addd680047414c34d6bdcd29737c2ac438727be"


def read_rows(name):
    with (ROOT / f"{name}.csv").open(newline="") as source:
        return list(csv.DictReader(source))


def describe(rows, key):
    values = [int(row[key]) for row in rows]
    return {"min": min(values), "mean": mean(values), "max": max(values)}


def summarize(name):
    rows = read_rows(name)
    expected = ["launch"]
    for cycle in range(10):
        for phase in ("staged", "closed"):
            expected += [f"cycle-{cycle}-{phase}-{second}s" for second in range(1, 31)]
    expected += ["lifecycle-complete"]
    assert [row["state"] for row in rows] == expected, name
    status = (ROOT / f"{name}.status.txt").read_text()
    assert status.startswith("exit_code=0\nexpected_exit_code=0\n"), name
    assert "lifecycle-complete," in status, name
    environment = (ROOT / f"{name}.environment.txt").read_text()
    fixture_hash = LARGE_HASH if name == "current-large" else TYPICAL_HASH
    assert f"{fixture_hash} " in environment, name
    assert "Signature=adhoc\n" in environment, name
    assert "character_cycles=10\n" in environment, name
    assert "target_stack_logging=0\n" in environment, name
    times = [float(row["system_uptime_seconds"]) for row in rows]
    gaps = [right - left for left, right in zip(times, times[1:])]
    assert min(gaps) > 0, name
    closed = [row for row in rows if "-closed-" in row["state"]]
    last_hold = [row for row in rows if row["state"].startswith("cycle-9-closed-")]
    endpoints = [row for row in closed if row["state"].endswith("-30s")]
    return {
        "samples": len(rows),
        "elapsed_seconds": times[-1] - times[0],
        "maximum_sample_gap_seconds": max(gaps),
        "peak_physical_footprint_bytes": max(int(row["peak_physical_footprint_bytes"]) for row in rows),
        "peak_rss_bytes": max(int(row["peak_rss_bytes"]) for row in rows),
        "final_physical_footprint_bytes": int(rows[-1]["physical_footprint_bytes"]),
        "final_rss_bytes": int(rows[-1]["rss_bytes"]),
        "all_closed_physical_footprint_bytes": describe(closed, "physical_footprint_bytes"),
        "last_closed_hold_physical_footprint_bytes": describe(last_hold, "physical_footprint_bytes"),
        "last_closed_hold_rss_bytes": describe(last_hold, "rss_bytes"),
        "closed_30s_endpoints": [
            {"state": row["state"], "physical_footprint_bytes": int(row["physical_footprint_bytes"]),
             "rss_bytes": int(row["rss_bytes"])} for row in endpoints
        ],
    }


negative = read_rows("invalid-zero")
assert [row["state"] for row in negative] == ["launch"]
negative_status = (ROOT / "invalid-zero.status.txt").read_text()
assert negative_status.startswith("exit_code=1\nexpected_exit_code=1\n")
assert "Image app probe failed: invalidCycleCount" in negative_status
summary = {name: summarize(name) for name in ("historical-typical", "current-typical", "current-large")}
default = read_rows("default-typical")
expected_default = ["launch"]
for iteration in range(10):
    expected_default += [f"prepared-{iteration}", f"import-{iteration}"]
expected_default += ["character-import-30s", "return-idle-30s"]
assert [row["state"] for row in default] == expected_default
assert (ROOT / "default-typical.status.txt").read_text() == "exit_code=0\nexpected_exit_code=0\n"
assert "character_lifecycle=0\n" in (ROOT / "default-typical.environment.txt").read_text()
summary["default-typical"] = {
    "samples": len(default),
    "peak_physical_footprint_bytes": max(int(row["peak_physical_footprint_bytes"]) for row in default),
    "final_physical_footprint_bytes": int(default[-1]["physical_footprint_bytes"]),
}
print(json.dumps(summary, indent=2, sort_keys=True))
