"""Flag size-matrix cells whose p95 is incompatible with the same work elsewhere.

The size matrix and the baseline measure the same request cost when the size is
the standard one (CPU 10, memory 32, IO 1024). If a cell of the matrix says the
request takes several times longer than the baseline cell with the same number
of clients, the number describes something other than the work: the usual cause
is contention on the shared VDI -> load balancer path, which is out of the
group's control. Such a cell is re-run rather than reported.

The ceiling scales with the work size, because more iterations of the CPU block
or more kilobytes do take longer:

    ceiling = max(factor * base_p95 * size / standard_size, floor_ms)

Usage:
    python scripts/check_cells.py results [--factor 2.5] [--floor 500]
"""

import argparse
import csv
import os
import sys

import summarize


def rows(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def main():
    parser = argparse.ArgumentParser(description="Check the size matrix against the baseline.")
    parser.add_argument("results")
    parser.add_argument("--factor", type=float, default=2.5)
    parser.add_argument("--floor", type=float, default=500.0,
                        help="minimum ceiling in ms, for the smallest sizes")
    args = parser.parse_args()

    base = {row["scenario"]: row
            for row in rows(os.path.join(args.results, "summary.csv"))}
    cells = rows(os.path.join(args.results, "summary-size.csv"))

    flagged = []
    for cell in cells:
        match = summarize.SIZED.match(cell["scenario"])
        if not match:
            continue
        profile, size, concurrency = match.group(1), int(match.group(2)), int(match.group(3))
        reference = base.get(f"{profile}-c{concurrency}")
        if reference is None:
            continue
        expected = float(reference["p95_ms"]) * size / summarize.STANDARD_SIZE[profile]
        ceiling = max(args.factor * expected, args.floor)
        p95 = float(cell["p95_ms"])
        status = "ok" if p95 <= ceiling else "ACIMA"
        print(f"{cell['scenario']:<24} p95={p95:>9.1f} ms  teto={ceiling:>9.1f} ms"
              f"  (base {profile}-c{concurrency} p95={reference['p95_ms']} ms)  {status}",
              file=sys.stderr)
        if p95 > ceiling:
            flagged.append(f"size-{profile}-s{size}-c{concurrency}")

    for cell in flagged:
        print(cell)


if __name__ == "__main__":
    main()
