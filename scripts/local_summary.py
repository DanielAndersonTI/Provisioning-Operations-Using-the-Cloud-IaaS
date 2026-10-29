"""Resumo de uma execucao de carga feita dentro da VM.

A carga local existe para um objetivo especifico: provar o comportamento do
servidor quando a demanda passa das vagas de trabalho, sem que o balanceador
compartilhado limite a chegada das requisicoes. Por isso o resumo mostra tambem
o motivo de cada erro (o 503 aparece discriminado).

Uso:
    python scripts/local_summary.py <results> <run_id>
"""

import csv
import os
import sys


def rows(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def main():
    results, run_id = sys.argv[1:3]

    row = next((r for r in rows(os.path.join(results, "measurements-local.csv"))
                if r["run_id"] == run_id), None)
    if row is None:
        print("execucao nao encontrada em measurements-local.csv:", run_id)
        return

    app = next((r for r in rows(os.path.join(results, "app-metrics-local.csv"))
                if r["run_id"] == run_id), None)

    print("execucao         :", run_id)
    print("url              :", row["url"])
    print("concorrencia     :", row["concurrency"], "cliente(s) dentro da VM")
    print("janela medida    :", row["duration_target_s"], "s")
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

    if app:
        print()
        print("contadores da aplicacao (delta da execucao):")
        print("  requisicoes    :", app["app_requests"])
        print("  aceitas (2xx)  :", app["app_ok"])
        print("  recusadas (503):", app["app_rejected"])
        print("  espera media   :", app["app_mean_wait_ms"], "ms")
        print("  trabalho medio :", app["app_mean_work_ms"], "ms")
        print("  em voo no pico :", app["app_max_inflight"])


if __name__ == "__main__":
    main()
