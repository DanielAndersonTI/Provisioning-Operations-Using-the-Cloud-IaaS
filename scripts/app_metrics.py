"""Turn two `/metrics` snapshots into one row of per-run application counters.

The endpoint returns cumulative numbers since the process started. Taking a
snapshot immediately before and immediately after a load run and subtracting
gives exactly what happened during that run, without restarting the service
between runs.

Usage:
    python scripts/app_metrics.py before.json after.json <run_id> <csv>
"""

import csv
import json
import os
import sys


FIELDS = [
    "run_id", "profile", "app_requests", "app_ok", "app_rejected", "app_failed",
    "app_completed", "app_mean_wait_ms", "app_mean_work_ms", "app_max_work_ms",
    "app_max_inflight", "app_inflight_end",
]


def main():
    before_path, after_path, run_id, out = sys.argv[1:5]

    with open(before_path, encoding="utf-8") as handle:
        before = json.load(handle)
    with open(after_path, encoding="utf-8") as handle:
        after = json.load(handle)

    completed = after["completed"] - before["completed"]
    wait = after["wait_seconds_total"] - before["wait_seconds_total"]
    work = after["work_seconds_total"] - before["work_seconds_total"]

    row = {
        "run_id": run_id,
        "profile": after["profile"],
        "app_requests": after["requests"] - before["requests"],
        "app_ok": after["ok"] - before["ok"],
        "app_rejected": after["rejected_503"] - before["rejected_503"],
        "app_failed": after["failed"] - before["failed"],
        "app_completed": completed,
        "app_mean_wait_ms": round(1000.0 * wait / completed, 3) if completed else 0.0,
        "app_mean_work_ms": round(1000.0 * work / completed, 3) if completed else 0.0,
        # Peaks are cumulative since the process started; the phase restarts the
        # services right before the measurements, so they cover this phase only.
        "app_max_work_ms": after["max_work_ms"],
        "app_max_inflight": after["max_inflight"],
        "app_inflight_end": after["inflight"],
    }

    new = not os.path.exists(out)
    with open(out, "a", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        if new:
            writer.writeheader()
        writer.writerow(row)

    print("metricas do app em", run_id, ":", row)


if __name__ == "__main__":
    main()
