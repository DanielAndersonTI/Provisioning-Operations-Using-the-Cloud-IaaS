"""Print the report block for a single load run.

Reads the three files a run produces -- the client measurements, the in-VM
resource samples and the application counters -- and prints one aligned block
that the phase script saves as evidence.

Usage:
    python scripts/run_summary.py results <run_id>
"""

import csv
import os
import statistics
import sys


def read_rows(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def find(rows, key, value):
    for row in rows:
        if row.get(key) == value:
            return row
    return None


def main():
    results, run_id = sys.argv[1:3]

    row = find(read_rows(os.path.join(results, "measurements-v2.csv")), "run_id", run_id)
    if row is None:
        print("execucao nao encontrada em measurements-v2.csv:", run_id)
        return

    samples = read_rows(os.path.join(results, f"resources-v2-{run_id}.csv"))
    app = find(read_rows(os.path.join(results, "app-metrics.csv")), "run_id", run_id)
    disks = [d for d in read_rows(os.path.join(results, "iostat.csv")) if d["run_id"] == run_id]

    print("execucao         :", run_id)
    print("url              :", row["url"])
    print("concorrencia     :", row["concurrency"], "cliente(s)")
    print("janela medida    :", row["duration_target_s"], "s (aquecimento descartado)")
    print()
    print("requisicoes      :", row["attempts"])
    print("sucessos         :", row["successes"])
    print("erros            :", row["errors"], row["errors_by_kind"] or "")
    print("taxa de erro     :", row["error_rate"])
    print("vazao (rps)      :", row["success_throughput_rps"], "(sucesso) /",
          row["throughput_rps"], "(total)")
    print("latencia media   :", row["mean_ms"], "ms")
    print("p50 / p95 / p99  :", row["p50_ms"], "/", row["p95_ms"], "/", row["p99_ms"], "ms")
    print("maximo           :", row["max_ms"], "ms")

    if samples:
        cpu = [float(s["cpu_percent"]) for s in samples]
        mem = [float(s["memory_percent"]) for s in samples]
        swap = [float(s["swap_used_mb"]) for s in samples]
        print()
        print("amostras do monitor:", len(samples), "(intervalo de 0,5 s)")
        print(f"cpu da VM        : media {statistics.mean(cpu):5.1f}%  pico {max(cpu):5.1f}%")
        print(f"memoria da VM    : media {statistics.mean(mem):5.1f}%  pico {max(mem):5.1f}%")
        print(f"swap em uso      : media {statistics.mean(swap):5.1f} MiB pico {max(swap):5.1f} MiB")

    if app:
        print()
        print("contadores da aplicacao (delta da execucao):")
        print("  requisicoes    :", app["app_requests"])
        print("  aceitas (2xx)  :", app["app_ok"])
        print("  recusadas (503):", app["app_rejected"])
        print("  espera media   :", app["app_mean_wait_ms"], "ms")
        print("  trabalho medio :", app["app_mean_work_ms"], "ms")
        print("  trabalho maximo:", app["app_max_work_ms"], "ms")
        print("  em voo no pico :", app["app_max_inflight"])

    for disk in disks:
        print()
        print(f"disco {disk['device']}: {disk['samples']} amostras de iostat")
        print(f"  ocupacao       : media {disk['util_mean']}%  pico {disk['util_max']}%")
        print(f"  fila (aqu-sz)  : media {disk['aqu_mean']}")
        print(f"  escritas       : {disk['w_s_mean']} req/s")
        print(f"  leituras       : {disk['r_s_mean']} req/s")
        print(f"  espera escrita : {disk['w_await_mean']} ms")
        print(f"  espera leitura : {disk['r_await_mean']} ms")


if __name__ == "__main__":
    main()
