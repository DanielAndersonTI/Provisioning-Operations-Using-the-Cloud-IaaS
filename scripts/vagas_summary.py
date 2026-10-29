"""Resumo de uma execucao da matriz de vagas.

A matriz de vagas existe para uma pergunta que os cenarios pela VIP nao
respondem: o limite do servidor vem do flavor ou do numero de unidades de
trabalho que ele aceita executar ao mesmo tempo? Para isso a mesma carga e
repetida com `--max-concurrency` diferente, com o servidor sozinho na VM e o
cliente rodando dentro dela - o balanceador compartilhado nunca chega a encher
as vagas.

O resumo mostra as tres coisas que mudam com o numero de vagas: a vazao de
sucesso, as recusas 503 (que crescem quando a demanda passa das vagas) e a
espera media pela vaga registrada dentro do processo.

Uso:
    python scripts/vagas_summary.py <results> <run_id> [<vagas>]
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
    slots = sys.argv[3] if len(sys.argv) > 3 else ""

    row = next((r for r in rows(os.path.join(results, "measurements-vagas.csv"))
                if r["run_id"] == run_id), None)
    if row is None:
        print("execucao nao encontrada em measurements-vagas.csv:", run_id)
        return

    app = next((r for r in rows(os.path.join(results, "app-metrics-vagas.csv"))
                if r["run_id"] == run_id), None)

    print("execucao         :", run_id)
    print("url              :", row["url"])
    print("vagas (servidor) :", slots or "?")
    print("clientes         :", row["concurrency"], "dentro da VM")
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

    if app:
        print()
        print("contadores da aplicacao (delta da execucao):")
        print("  recusadas (503):", app["app_rejected"])
        print("  espera media   :", app["app_mean_wait_ms"], "ms")
        print("  trabalho medio :", app["app_mean_work_ms"], "ms")
        print("  em voo no pico :", app["app_max_inflight"])


if __name__ == "__main__":
    main()
