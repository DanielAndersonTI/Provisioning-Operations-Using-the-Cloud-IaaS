"""Consolidate the load runs into the summary tables the report uses.

The raw files stay untouched; every table is derived from them, so a table and
the figure drawn from it can never disagree.

Inputs (in `results/`):
    measurements.csv        first pass, 45 s windows, one run per scenario
    measurements-v2.csv     size x concurrency, saturation, repetitions, the
                            medium-flavor pass and the reconciliation re-runs
    measurements-misto.csv  mixed request sizes at fixed concurrency
    measurements-vagas.csv  in-VM runs with a chosen --max-concurrency
    resources-*.csv         in-VM samples, one file per run
    app-metrics*.csv        per-run application counters

Outputs (in `results/`):
    summary.csv            the nine baseline scenarios, mean and sd over 3 runs
    summary-size.csv       size x concurrency matrix
    summary-saturation.csv concurrency beyond the configured slots
    summary-medium.csv     same scenarios measured on the 2-vCPU flavor
    summary-misto.csv      mixed request sizes
    summary-vagas.csv      number of work slots x demand

Two rules keep the tables honest:

  * a baseline scenario measured again in a later pass uses only the new
    repetitions - the shared load balancer behaves differently at different
    hours, so mixing the passes would compare conditions;
  * a cell of the size, saturation or flavor matrices drops its original single
    run as soon as repetitions exist (`-r2`, `-r3`, ...) and averages those.
    Cells were re-measured when the number disagreed with the same work
    measured elsewhere, so the original one is the suspect sample, not data to
    be averaged in.

The `size` column is filled for the baseline rows too (10 for CPU, 32 for
memory, 1024 for IO). Leaving it empty there made the standard scenario look
like a different experiment from the same scenario in the size matrix.
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

BASELINE = re.compile(r"^(cpu|memory|io)-c(\d+)(?:-r(\d+))?$")
SIZED = re.compile(r"^size-(cpu|memory|io)-s(\d+)-c(\d+)(?:-r(\d+))?$")
SATURATED = re.compile(r"^sat-(cpu|memory|io)-s(\d+)-c(\d+)(?:-r(\d+))?$")
MEDIUM = re.compile(r"^med-(cpu|memory|io)-s(\d+)-c(\d+)(?:-r(\d+))?$")
VAGAS = re.compile(r"^vagas-(cpu|io)-w(\d+)-c(\d+)(?:-r(\d+))?$")
MISTO = re.compile(r"^misto-(cpu|memory|io)-c(\d+)(?:-r(\d+))?$")

# The size each profile uses in the baseline scenario and in the slot matrix.
STANDARD_SIZE = {"cpu": 10, "memory": 32, "io": 1024}

# The sizes a mixed run draws from - the same list the phase passes to
# `load_test.py --sizes`.
MIXED_SIZES = {"cpu": "5,10,15", "memory": "16,32,48", "io": "512,1024,1536"}


def rows(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def resources(results, run_id, directory):
    return rows(os.path.join(results, directory.format(run_id)))


def resource_stats(samples):
    cpu = [float(s["cpu_percent"]) for s in samples]
    mem = [float(s["memory_percent"]) for s in samples]
    swap = [float(s["swap_used_mb"]) for s in samples]
    if not cpu:
        return 0.0, 0.0, 0.0, 0.0, 0.0
    return (round(statistics.mean(cpu), 1), round(max(cpu), 1),
            round(statistics.mean(mem), 1), round(max(mem), 1), round(max(swap), 1))


def load(results, measurements, resource_pattern, app):
    """Turn one measurement file into run_id -> numbers."""
    collected = {}
    for row in rows(os.path.join(results, measurements)):
        run_id = row["run_id"]
        cpu_mean, cpu_max, mem_mean, mem_max, swap_max = resource_stats(
            resources(results, run_id, resource_pattern)
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
    return collected


def collect(results):
    """Return (primeira_passagem, passagens_seguintes) como dicts run_id -> numeros.

    A primeira passagem e a fase 10; as seguintes, as repeticoes e matrizes da
    fase 12 em diante. Elas ficam separadas porque foram medidas em momentos
    diferentes e o balanceador compartilhado muda de comportamento ao longo do
    dia.
    """
    app = {row["run_id"]: row for row in rows(os.path.join(results, "app-metrics.csv"))}
    app_vagas = {row["run_id"]: row
                 for row in rows(os.path.join(results, "app-metrics-vagas.csv"))}

    first = load(results, "measurements.csv", "resources-{}.csv", app)
    second = {}
    second.update(load(results, "measurements-v2.csv", "resources-v2-{}.csv", app))
    second.update(load(results, "measurements-misto.csv", "resources-v2-{}.csv", app))
    second.update(load(results, "measurements-vagas.csv",
                       "resources-vagas-{}.csv", app_vagas))
    return first, second


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

    baseline = {}
    latest = {"size": {}, "sat": {}, "med": {}}
    vagas, misto = {}, {}

    # Cenario que tem repeticao nova usa so as repeticoes novas: misturar a
    # medicao da fase 10 com as de agora juntaria condicoes diferentes.
    repetidos = {run_id.split("-r")[0] for run_id in second_pass if BASELINE.match(run_id)}
    for run_id, run in sorted(first_pass.items()):
        match = BASELINE.match(run_id)
        if match and f"{match.group(1)}-c{match.group(2)}" not in repetidos:
            baseline.setdefault((match.group(1), int(match.group(2))), []).append(run)

    for run_id, run in sorted(second_pass.items()):
        match = BASELINE.match(run_id)
        if match:
            baseline.setdefault((match.group(1), int(match.group(2))), []).append(run)
            continue

        match = VAGAS.match(run_id)
        if match:
            key = (match.group(1), int(match.group(2)), int(match.group(3)))
            vagas.setdefault(key, []).append(run)
            continue

        match = MISTO.match(run_id)
        if match:
            key = (match.group(1), int(match.group(2)))
            misto.setdefault(key, []).append(run)
            continue

        for pattern, label in ((SIZED, "size"), (SATURATED, "sat"), (MEDIUM, "med")):
            match = pattern.match(run_id)
            if match:
                profile, size, concurrency = (match.group(1), int(match.group(2)),
                                              int(match.group(3)))
                # 0 marca a execucao original; 2, 3... as repeticoes.
                repetition = int(match.group(4) or 0)
                cell = latest[label].setdefault((profile, size, concurrency), {})
                cell[repetition] = run
                break

    base_rows = [build(f"{profile}-c{concurrency}", profile, STANDARD_SIZE[profile],
                       concurrency, group)
                 for (profile, concurrency), group in sorted(baseline.items())]

    def cells(label):
        """Uma linha por celula, com a media das repeticoes quando existem.

        A execucao original de uma matriz e de uma vez so; quando a celula ganhou
        repeticoes (por duvida no numero ou por reconciliacao), sao as repeticoes
        que valem e a original sai da conta - ela pode ter pego o pico de outro
        grupo no caminho compartilhado.
        """
        out = []
        for (profile, size, concurrency), by_rep in sorted(latest[label].items()):
            group = ([run for rep, run in sorted(by_rep.items()) if rep > 0]
                     or [by_rep[0]])
            out.append(build(f"{label}-{profile}-s{size}-c{concurrency}",
                             profile, size, concurrency, group))
        return out

    vagas_rows = [build(f"vagas-{profile}-w{slots}-c{concurrency}", profile,
                        STANDARD_SIZE[profile], concurrency, group)
                  for (profile, slots, concurrency), group in sorted(vagas.items())]
    misto_rows = [build(f"misto-{profile}-c{concurrency}", profile,
                        MIXED_SIZES[profile], concurrency, group)
                  for (profile, concurrency), group in sorted(misto.items())]

    write(os.path.join(results, "summary.csv"), base_rows)
    write(os.path.join(results, "summary-size.csv"), cells("size"))
    write(os.path.join(results, "summary-saturation.csv"), cells("sat"))
    write(os.path.join(results, "summary-medium.csv"), cells("med"))
    write(os.path.join(results, "summary-misto.csv"), misto_rows)
    write(os.path.join(results, "summary-vagas.csv"), vagas_rows)

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
