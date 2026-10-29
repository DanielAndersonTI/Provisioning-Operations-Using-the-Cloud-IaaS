"""Consolidate the load runs into the summary tables the report uses.

The raw files stay untouched; every table is derived from them, so a table and
the figure drawn from it can never disagree.

Inputs (in `results/`):
    measurements.csv       first pass, 45 s windows, one run per scenario
    measurements-v2.csv    size x concurrency, saturation, repetitions and the
                           medium-flavor pass
    resources-*.csv        in-VM samples, one file per run
    app-metrics.csv        per-run application counters (second pass only)

Outputs (in `results/`):
    summary.csv            the nine baseline scenarios, mean and sd over 3 runs
    summary-size.csv       size x concurrency matrix
    summary-saturation.csv concurrency beyond the configured slots
    summary-medium.csv     same scenarios measured on the 2-vCPU flavor
"""

import csv
import os
import re
import statistics
import sys


FIELDS = [
    "scenario", "profile", "size", "concurrency", "reps",
    "attempts", "successes", "errors", "error_rate",
    "throughput_rps", "success_throughput_rps", "success_throughput_rps_sd",
    "mean_ms", "mean_ms_sd", "p50_ms", "p95_ms", "p95_ms_sd", "p99_ms", "max_ms",
    "cpu_mean", "cpu_max", "mem_mean", "mem_max", "swap_max",
    "app_rejected", "app_mean_wait_ms", "app_mean_work_ms", "path_overhead_ms",
]

BASELINE = re.compile(r"^(cpu|memory|io)-c(\d+)(?:-r\d+)?$")
SIZED = re.compile(r"^size-(cpu|memory|io)-s(\d+)-c(\d+)$")
SATURATED = re.compile(r"^sat-(cpu|memory|io)-s(\d+)-c(\d+)$")
MEDIUM = re.compile(r"^med-(cpu|memory|io)-s(\d+)-c(\d+)$")


def rows(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def resources(results, run_id, second_pass):
    name = f"resources-v2-{run_id}.csv" if second_pass else f"resources-{run_id}.csv"
    return rows(os.path.join(results, name))


def resource_stats(samples):
    cpu = [float(s["cpu_percent"]) for s in samples]
    mem = [float(s["memory_percent"]) for s in samples]
    swap = [float(s["swap_used_mb"]) for s in samples]
    if not cpu:
        return 0.0, 0.0, 0.0, 0.0, 0.0
    return (round(statistics.mean(cpu), 1), round(max(cpu), 1),
            round(statistics.mean(mem), 1), round(max(mem), 1), round(max(swap), 1))


def collect(results):
    """Return (primeira_passagem, segunda_passagem) como dicts run_id -> numeros.

    A primeira passagem e a fase 10; a segunda, as repeticoes e matrizes da fase
    12. Elas ficam separadas porque foram medidas em momentos diferentes e o
    balanceador compartilhado muda de comportamento ao longo do dia.
    """
    app = {row["run_id"]: row for row in rows(os.path.join(results, "app-metrics.csv"))}
    passes = ({}, {})
    for second_pass, filename in ((False, "measurements.csv"), (True, "measurements-v2.csv")):
        collected = passes[1 if second_pass else 0]
        for row in rows(os.path.join(results, filename)):
            run_id = row["run_id"]
            cpu_mean, cpu_max, mem_mean, mem_max, swap_max = resource_stats(
                resources(results, run_id, second_pass)
            )
            counters = app.get(run_id, {})
            collected[run_id] = {
                "run_id": run_id,
                "attempts": int(row["attempts"]),
                "successes": int(row["successes"]),
                "errors": int(row["errors"]),
                "error_rate": float(row["error_rate"]),
                "throughput_rps": float(row["throughput_rps"]),
                "success_throughput_rps": float(row["success_throughput_rps"]),
                "mean_ms": float(row["mean_ms"]),
                "p50_ms": float(row["p50_ms"]),
                "p95_ms": float(row["p95_ms"]),
                "p99_ms": float(row["p99_ms"]),
                "max_ms": float(row["max_ms"]),
                "cpu_mean": cpu_mean, "cpu_max": cpu_max,
                "mem_mean": mem_mean, "mem_max": mem_max, "swap_max": swap_max,
                "app_rejected": int(counters.get("app_rejected") or 0),
                "app_mean_wait_ms": float(counters.get("app_mean_wait_ms") or 0.0),
                "app_mean_work_ms": float(counters.get("app_mean_work_ms") or 0.0),
                "has_app": bool(counters),
            }
    return passes


def mean(values):
    return statistics.mean(values) if values else 0.0


def sd(values):
    return statistics.stdev(values) if len(values) > 1 else 0.0


def build(scenario, profile, size, concurrency, group):
    """One summary row from one or more runs of the same scenario."""
    return {
        "scenario": scenario,
        "profile": profile,
        "size": size,
        "concurrency": concurrency,
        "reps": len(group),
        "attempts": sum(r["attempts"] for r in group),
        "successes": sum(r["successes"] for r in group),
        "errors": sum(r["errors"] for r in group),
        "error_rate": round(mean([r["error_rate"] for r in group]), 3),
        "throughput_rps": round(mean([r["throughput_rps"] for r in group]), 4),
        "success_throughput_rps": round(mean([r["success_throughput_rps"] for r in group]), 4),
        "success_throughput_rps_sd": round(sd([r["success_throughput_rps"] for r in group]), 4),
        "mean_ms": round(mean([r["mean_ms"] for r in group]), 3),
        "mean_ms_sd": round(sd([r["mean_ms"] for r in group]), 3),
        "p50_ms": round(mean([r["p50_ms"] for r in group]), 3),
        "p95_ms": round(mean([r["p95_ms"] for r in group]), 3),
        "p95_ms_sd": round(sd([r["p95_ms"] for r in group]), 3),
        "p99_ms": round(mean([r["p99_ms"] for r in group]), 3),
        "max_ms": round(max(r["max_ms"] for r in group), 3),
        "cpu_mean": round(mean([r["cpu_mean"] for r in group]), 1),
        "cpu_max": round(max(r["cpu_max"] for r in group), 1),
        "mem_mean": round(mean([r["mem_mean"] for r in group]), 1),
        "mem_max": round(max(r["mem_max"] for r in group), 1),
        "swap_max": round(max(r["swap_max"] for r in group), 1),
        "app_rejected": sum(r["app_rejected"] for r in group),
        "app_mean_wait_ms": round(mean([r["app_mean_wait_ms"] for r in group]), 3),
        "app_mean_work_ms": round(mean([r["app_mean_work_ms"] for r in group]), 3),
        # Diferenca entre o que o cliente ve e o que o servidor gastou: conexao,
        # balanceador e caminho VDI -> nuvem. Vazio quando nao ha contador do app.
        "path_overhead_ms": (
            round(mean([r["mean_ms"] for r in group])
                  - mean([r["app_mean_work_ms"] for r in group if r["has_app"]]), 3)
            if any(r["has_app"] for r in group) else ""
        ),
    }


def write(path, out):
    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(out)
    print(f"{os.path.basename(path):<24} {len(out):>3} linhas")


def main():
    results = sys.argv[1] if len(sys.argv) > 1 else "results"
    first_pass, second_pass = collect(results)
    runs = {**first_pass, **second_pass}

    baseline, sized, saturated, medium = {}, [], [], []

    # Cenario que tem repeticao nova usa so as repeticoes novas: misturar a
    # medicao da fase 10 com as de agora juntaria condicoes diferentes.
    repetidos = {run_id.split("-r")[0] for run_id in second_pass if BASELINE.match(run_id)}
    for run_id, run in sorted(first_pass.items()):
        match = BASELINE.match(run_id)
        if match and f"{match.group(1)}-c{match.group(2)}" not in repetidos:
            profile, concurrency = match.group(1), int(match.group(2))
            baseline.setdefault((profile, concurrency), []).append(run)

    for run_id, run in sorted(second_pass.items()):
        match = BASELINE.match(run_id)
        if match:
            profile, concurrency = match.group(1), int(match.group(2))
            baseline.setdefault((profile, concurrency), []).append(run)
            continue

        for pattern, bucket, label in (
            (SIZED, sized, "size"),
            (SATURATED, saturated, "sat"),
            (MEDIUM, medium, "med"),
        ):
            match = pattern.match(run_id)
            if match:
                profile, size, concurrency = match.group(1), int(match.group(2)), int(match.group(3))
                bucket.append(build(f"{label}-{profile}-s{size}-c{concurrency}",
                                    profile, size, concurrency, [run]))
                break

    base_rows = [build(f"{profile}-c{concurrency}", profile, "", concurrency, group)
                 for (profile, concurrency), group in sorted(baseline.items())]

    write(os.path.join(results, "summary.csv"), base_rows)
    write(os.path.join(results, "summary-size.csv"), sized)
    write(os.path.join(results, "summary-saturation.csv"), saturated)
    write(os.path.join(results, "summary-medium.csv"), medium)

    header = (f"{'cenario':<10}{'rep':>4}{'conc':>5}{'req':>7}{'ok':>7}{'erro':>6}"
              f"{'rps':>9}{'med_ms':>9}{'p95_ms':>9}{'cpu%':>7}{'ram%':>7}")
    print()
    print(header)
    print("-" * len(header))
    for item in base_rows:
        print(f"{item['scenario']:<10}{item['reps']:>4}{item['concurrency']:>5}"
              f"{item['attempts']:>7}{item['successes']:>7}{item['errors']:>6}"
              f"{item['success_throughput_rps']:>9}{item['mean_ms']:>9}"
              f"{item['p95_ms']:>9}{item['cpu_mean']:>7}{item['mem_mean']:>7}")


if __name__ == "__main__":
    main()
