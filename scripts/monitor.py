"""VM-side resource monitor.

Run this INSIDE the VM, at the same time as the external load generator on the
host. It records what the guest operating system sees of the resources the
experiment provisions, which is what the report has to relate to demand.

    python scripts/monitor.py --scenario C1 --seconds 200 --interval 0.5

Start it shortly before the host begins generating load and let it run a little
past the end. `run_scenario.py` on the host records the UTC window of every
demand level, and the analysis uses those windows to attribute samples to a
level, so overlapping slightly is safe while missing time is not.

Reading the samples: `cpu_percent` is the average over the preceding
`--interval`, so the sample stamped t describes the window (t - interval, t].
`swap_used_mb` matters for the memory-bound profile, where a provisioned RAM
shortage shows up as swapping rather than as an outright failure.
"""

import argparse
import csv
import datetime
import os
import time
from pathlib import Path

import psutil


FIELDNAMES = [
    "date_utc",
    "run_id",
    "scenario",
    "cpu_percent",
    "cpu_count",
    "memory_used_mb",
    "memory_percent",
    "swap_used_mb",
    "load_avg_1m",
]


def load_average():
    """One-minute load average, where the platform provides one."""
    try:
        return round(os.getloadavg()[0], 3)
    except (AttributeError, OSError):
        return ""


def main():
    parser = argparse.ArgumentParser(description="VM-side resource monitor.")
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--seconds", type=float, default=200.0)
    parser.add_argument("--interval", type=float, default=0.5)
    parser.add_argument("--run-id", default="")
    parser.add_argument("--out", default="results/resources.csv")
    args = parser.parse_args()

    if args.seconds <= 0:
        parser.error("--seconds must be positive")
    if args.interval <= 0:
        parser.error("--interval must be positive")

    target = Path(args.out)
    target.parent.mkdir(parents=True, exist_ok=True)
    has_content = target.exists() and target.stat().st_size > 0

    if has_content:
        with target.open(encoding="utf-8", newline="") as handle:
            header = handle.readline().strip().split(",")
        if header != FIELDNAMES:
            raise SystemExit(
                f"{target} was written with a different set of columns.\n"
                f"  expected: {','.join(FIELDNAMES)}\n"
                f"  found:    {','.join(header)}\n"
                "Move or delete that file before recording new samples."
            )

    with target.open("a", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
        if not has_content:
            writer.writeheader()

        psutil.cpu_percent(interval=None)  # prime the first reading
        deadline = time.monotonic() + args.seconds
        samples = 0
        while time.monotonic() < deadline:
            cpu = psutil.cpu_percent(interval=args.interval)
            memory = psutil.virtual_memory()
            swap = psutil.swap_memory()
            writer.writerow(
                {
                    "date_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(
                        timespec="milliseconds"
                    ),
                    "run_id": args.run_id,
                    "scenario": args.scenario,
                    "cpu_percent": cpu,
                    "cpu_count": psutil.cpu_count(logical=True),
                    "memory_used_mb": round(memory.used / (1024 * 1024), 2),
                    "memory_percent": memory.percent,
                    "swap_used_mb": round(swap.used / (1024 * 1024), 2),
                    "load_avg_1m": load_average(),
                }
            )
            handle.flush()
            samples += 1
            print(
                f"{samples:5d}  cpu={cpu:5.1f}%  "
                f"ram={memory.percent:5.1f}%  swap={swap.used / (1024 * 1024):7.1f} MiB",
                flush=True,
            )

    print(f"Recorded {samples} samples for {args.scenario} into {target}")


if __name__ == "__main__":
    main()
