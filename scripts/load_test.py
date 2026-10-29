"""External load generator.

Run this on the HOST, or on any machine outside the VM. Client-observed latency
and throughput have to be measured here rather than inside the application:
in-process timings miss connection setup, OS scheduling and queueing at the
server, which is exactly what a provisioning experiment needs to expose.

Two modes:

  duration  (use this for the reported results)
      Keep `--concurrency` clients busy for `--duration` seconds. Every level
      runs for the same wall-clock window, so levels stay comparable even when
      throughput collapses.

  requests
      Fire a fixed number of requests. Convenient for quick checks; the
      wall-clock window then varies with throughput, so avoid it for the
      measurements you report.

Examples:
    python scripts/load_test.py --url http://127.0.0.1:8080/work?size=60000 \
        --scenario C1 --level 1 --concurrency 1 --duration 30

    python scripts/load_test.py --url http://127.0.0.1:8080/work?size=60000 \
        --scenario C1 --level 4 --concurrency 4 --requests 40

    # mixed request sizes in the same window
    python scripts/load_test.py --url http://127.0.0.1:8080/work?size=10 \
        --sizes 5,10,20 --scenario C1 --level mixed --concurrency 4 --duration 30

`--sizes` replaces the size of `--url` with a draw from the given list, per
request. The run then sees a distribution of request costs instead of one cost:
the mean latency is the mean over the mixture, and p95 is pulled towards the
tail of the largest size. The `url` column records the template as
`...?size=5,10,20` so a mixed run is never mistaken for a single-size one.

Reading the throughput columns: `elapsed_s` covers the whole run, including the
ramp-down while the last in-flight requests finish, so throughput is slightly
understated. The tail is at most one request duration, which is negligible at
high demand and visible only at the lowest levels. `success_throughput_rps`
counts only requests that returned 2xx, so it is the column to plot once the
server starts rejecting work.
"""

import argparse
import csv
import datetime
import json
import math
import os
import random
import socket
import statistics
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import urlopen


FIELDNAMES = [
    "date_utc",
    "run_id",
    "scenario",
    "level",
    "url",
    "concurrency",
    "mode",
    "requests_target",
    "duration_target_s",
    "elapsed_s",
    "attempts",
    "successes",
    "errors",
    "error_rate",
    "errors_by_kind",
    "throughput_rps",
    "success_throughput_rps",
    "mean_ms",
    "p50_ms",
    "p95_ms",
    "p99_ms",
    "min_ms",
    "max_ms",
    "client_host",
    "client_cpu_count",
]


def request_once(url, timeout):
    """Perform one request and return (ok, error_kind, seconds)."""
    started = time.perf_counter()
    try:
        with urlopen(url, timeout=timeout) as response:
            response.read()
            status = response.status
        ok = 200 <= status < 300
        kind = "" if ok else f"http_{status}"
    except TimeoutError:
        ok, kind = False, "timeout"
    except HTTPError as error:
        # Includes the 503 the applications return once every work slot is busy.
        ok, kind = False, f"http_{error.code}"
        try:
            error.read()
        except OSError:
            pass
    except URLError as error:
        if isinstance(error.reason, TimeoutError):
            ok, kind = False, "timeout"
        else:
            ok, kind = False, "connection_error"
    except OSError:
        ok, kind = False, "connection_error"
    return ok, kind, time.perf_counter() - started


def with_size(url, size):
    """Return `url` with its `size` parameter set to `size`."""
    parts = urlsplit(url)
    query = [(key, value) for key, value in parse_qsl(parts.query, keep_blank_values=True)
             if key != "size"]
    query.append(("size", str(size)))
    return urlunsplit((parts.scheme, parts.netloc, parts.path,
                       urlencode(query), parts.fragment))


def size_urls(url, sizes):
    """Expand `--sizes` into the URLs a mixed run draws from."""
    if not sizes:
        return [url]
    return [with_size(url, size) for size in sizes]


def run_for_duration(urls, timeout, concurrency, seconds):
    """Keep `concurrency` clients busy for `seconds`, returning samples."""
    deadline = time.perf_counter() + seconds
    samples = []
    collected = threading.Lock()
    # One size means one URL; several mean each request draws a size, so the
    # window sees the cost distribution and not a single cost.
    pick = (lambda: random.choice(urls)) if len(urls) > 1 else (lambda: urls[0])

    def worker():
        local = []
        while time.perf_counter() < deadline:
            local.append(request_once(pick(), timeout))
        with collected:
            samples.extend(local)

    started = time.perf_counter()
    threads = [threading.Thread(target=worker) for _ in range(concurrency)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return samples, time.perf_counter() - started


def run_fixed_count(urls, timeout, concurrency, requests):
    """Fire exactly `requests` requests across `concurrency` clients."""
    pick = (lambda: random.choice(urls)) if len(urls) > 1 else (lambda: urls[0])
    started = time.perf_counter()
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        futures = [pool.submit(request_once, pick(), timeout) for _ in range(requests)]
        samples = [future.result() for future in as_completed(futures)]
    return samples, time.perf_counter() - started


def measure(urls, concurrency, timeout, duration=None, requests=None):
    """Run one load level. Returns (samples, elapsed_seconds, mode)."""
    if duration is not None:
        samples, elapsed = run_for_duration(urls, timeout, concurrency, duration)
        return samples, elapsed, "duration"
    samples, elapsed = run_fixed_count(urls, timeout, concurrency, requests)
    return samples, elapsed, "requests"


def percentile(values, fraction):
    """Percentile with linear interpolation, matching the usual convention."""
    if not values:
        return float("nan")
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = fraction * (len(ordered) - 1)
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def build_row(
    run_id,
    scenario,
    level,
    url,
    concurrency,
    mode,
    requests_target,
    duration_target,
    samples,
    elapsed,
):
    """Turn raw samples into the single CSV row that represents this run."""
    durations_ms = [seconds * 1000 for _, _, seconds in samples]
    attempts = len(samples)
    successes = sum(1 for ok, _, _ in samples if ok)
    errors = attempts - successes

    counts = {}
    for ok, kind, _ in samples:
        if not ok:
            counts[kind] = counts.get(kind, 0) + 1

    return {
        "date_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(
            timespec="seconds"
        ),
        "run_id": run_id,
        "scenario": scenario,
        "level": level,
        "url": url,
        "concurrency": concurrency,
        "mode": mode,
        "requests_target": "" if requests_target is None else requests_target,
        "duration_target_s": "" if duration_target is None else duration_target,
        "elapsed_s": round(elapsed, 4),
        "attempts": attempts,
        "successes": successes,
        "errors": errors,
        "error_rate": round(errors / attempts, 4) if attempts else "",
        "errors_by_kind": ";".join(f"{k}={v}" for k, v in sorted(counts.items())),
        "throughput_rps": round(attempts / elapsed, 4) if elapsed else "",
        "success_throughput_rps": round(successes / elapsed, 4) if elapsed else "",
        "mean_ms": round(statistics.fmean(durations_ms), 3) if durations_ms else "",
        "p50_ms": round(percentile(durations_ms, 0.50), 3) if durations_ms else "",
        "p95_ms": round(percentile(durations_ms, 0.95), 3) if durations_ms else "",
        "p99_ms": round(percentile(durations_ms, 0.99), 3) if durations_ms else "",
        "min_ms": round(min(durations_ms), 3) if durations_ms else "",
        "max_ms": round(max(durations_ms), 3) if durations_ms else "",
        "client_host": socket.gethostname(),
        "client_cpu_count": os.cpu_count(),
    }


def write_row(path, row):
    """Append a row, refusing to mix incompatible column layouts in one file."""
    target = Path(path)
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
                "Move or delete that file before recording runs in the new format."
            )

    with target.open("a", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
        if not has_content:
            writer.writeheader()
        writer.writerow(row)


def main():
    parser = argparse.ArgumentParser(description="External load generator.")
    parser.add_argument("--url", required=True, help="full work URL, including ?size=")
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--level", default="", help="demand level label for this run")
    parser.add_argument("--concurrency", type=int, required=True)
    parser.add_argument("--duration", type=float, help="seconds to keep clients busy")
    parser.add_argument("--requests", type=int, help="fixed request count instead")
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--run-id", default="")
    parser.add_argument(
        "--sizes",
        default="",
        help="comma-separated sizes; each request draws one (mixed workload)",
    )
    parser.add_argument("--out", default="results/measurements.csv")
    args = parser.parse_args()

    if args.concurrency < 1:
        parser.error("--concurrency must be at least 1")
    if (args.duration is None) == (args.requests is None):
        parser.error("give exactly one of --duration or --requests")
    if args.duration is not None and args.duration <= 0:
        parser.error("--duration must be positive")
    if args.requests is not None and args.requests < 1:
        parser.error("--requests must be at least 1")

    sizes = [int(value) for value in args.sizes.split(",") if value.strip()]
    if any(size < 1 for size in sizes):
        parser.error("--sizes values must be at least 1")

    run_id = args.run_id or f"{args.scenario}-L{args.level or args.concurrency}"
    record_url = (with_size(args.url, ",".join(str(size) for size in sizes))
                  if sizes else args.url)
    samples, elapsed, mode = measure(
        size_urls(args.url, sizes), args.concurrency, args.timeout,
        args.duration, args.requests
    )
    row = build_row(
        run_id,
        args.scenario,
        args.level,
        record_url,
        args.concurrency,
        mode,
        args.requests,
        args.duration,
        samples,
        elapsed,
    )
    write_row(args.out, row)
    print(json.dumps(row, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
