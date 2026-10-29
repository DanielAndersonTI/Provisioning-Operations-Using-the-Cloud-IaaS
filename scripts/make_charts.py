"""Gera os graficos do relatorio a partir de results/summary.csv.

Uso:
    python scripts/make_charts.py            # le results/summary.csv
    python scripts/make_charts.py --out docs/graficos

Tres figuras:
    latencia.png   p50 e p95 por concorrencia, um painel por perfil
    vazao.png      requisicoes por segundo bem-sucedidas, uma linha por perfil
    uso-vm.png     CPU e memoria da VM por concorrencia, um painel por perfil

As cores sao as tres primeiras da paleta categorica validada (azul, laranja,
agua), que passam o teste de daltonismo para todos os pares. Cada figura tem no
maximo tres series.
"""

import argparse
import csv
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parent.parent

# Paleta categorica validada: azul, laranja, agua.
AZUL = "#2a78d6"
LARANJA = "#eb6834"
AGUA = "#1baf7a"
TINTA = "#0b0b0b"
TINTA_2 = "#52514e"
GRADE = "#e4e3df"
FUNDO = "#fcfcfb"

PERFIS = [("cpu", "CPU-bound"), ("memory", "Memory-bound"), ("io", "IO-bound")]
CORES_POR_PERFIL = {"cpu": AZUL, "memory": LARANJA, "io": AGUA}


def carregar(caminho):
    with open(caminho, encoding="utf-8", newline="") as handle:
        linhas = list(csv.DictReader(handle))
    dados = defaultdict(dict)
    for linha in linhas:
        # O cenario se chama cpu-c1; o perfil e a parte antes do hifen.
        perfil = linha["scenario"].split("-")[0]
        conc = int(linha["concurrency"])
        dados[perfil][conc] = {
            "p50": float(linha["p50_ms"]),
            "p95": float(linha["p95_ms"]),
            "rps": float(linha["success_throughput_rps"]),
            "cpu": float(linha["cpu_mean"]),
            "ram": float(linha["mem_mean"]),
            "erros": int(linha["errors"]),
        }
    return dados


def estilo():
    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "font.size": 10,
        "axes.edgecolor": GRADE,
        "axes.labelcolor": TINTA_2,
        "axes.titlecolor": TINTA,
        "axes.facecolor": FUNDO,
        "figure.facecolor": FUNDO,
        "xtick.color": TINTA_2,
        "ytick.color": TINTA_2,
        "grid.color": GRADE,
        "grid.linewidth": 0.8,
        "axes.spines.top": False,
        "axes.spines.right": False,
    })


def eixo_y_grid(ax):
    ax.grid(axis="y", linestyle="-", linewidth=0.8, color=GRADE)
    ax.set_axisbelow(True)


def figura_latencia(dados, destino):
    fig, eixos = plt.subplots(1, 3, figsize=(12, 3.8), sharey=True)
    for ax, (perfil, titulo) in zip(eixos, PERFIS):
        concs = sorted(dados[perfil])
        p50 = [dados[perfil][c]["p50"] for c in concs]
        p95 = [dados[perfil][c]["p95"] for c in concs]
        ax.plot(concs, p50, color=AZUL, linewidth=2, marker="o", markersize=8,
                label="p50")
        ax.plot(concs, p95, color=LARANJA, linewidth=2, marker="s", markersize=8,
                label="p95")
        for valores, cor in ((p50, AZUL), (p95, LARANJA)):
            ax.annotate(f"{valores[-1]:.0f}", (concs[-1], valores[-1]),
                        textcoords="offset points", xytext=(8, 0),
                        va="center", fontsize=9, color=cor)
        ax.set_title(titulo, loc="left", fontsize=11, pad=8)
        ax.set_xlabel("clientes concorrentes")
        ax.set_xticks(concs)
        ax.set_xlim(0.6, 4.6)
        eixo_y_grid(ax)
        ax.legend(frameon=False, loc="upper left", fontsize=9)
    eixos[0].set_ylabel("latência (ms)")
    fig.suptitle("Latência vista pelo cliente, por concorrência",
                 x=0.01, ha="left", fontsize=13)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(destino, dpi=160)
    plt.close(fig)


def figura_vazao(dados, destino):
    fig, ax = plt.subplots(figsize=(7.2, 4))
    for perfil, titulo in PERFIS:
        concs = sorted(dados[perfil])
        rps = [dados[perfil][c]["rps"] for c in concs]
        ax.plot(concs, rps, color=CORES_POR_PERFIL[perfil], linewidth=2,
                marker="o", markersize=8, label=titulo)
        ax.annotate(f"{rps[-1]:.0f}", (concs[-1], rps[-1]),
                    textcoords="offset points", xytext=(8, 0), va="center",
                    fontsize=9, color=CORES_POR_PERFIL[perfil])
    ax.set_xlabel("clientes concorrentes")
    ax.set_ylabel("requisições por segundo (2xx)")
    ax.set_xticks([1, 2, 4])
    ax.set_xlim(0.6, 4.6)
    eixo_y_grid(ax)
    ax.legend(frameon=False, loc="upper left", fontsize=9)
    ax.set_title("Vazão bem-sucedida por concorrência", loc="left", fontsize=13, pad=10)
    fig.tight_layout()
    fig.savefig(destino, dpi=160)
    plt.close(fig)


def figura_uso(dados, destino):
    fig, eixos = plt.subplots(1, 3, figsize=(12, 3.8), sharey=True)
    for ax, (perfil, titulo) in zip(eixos, PERFIS):
        concs = sorted(dados[perfil])
        cpu = [dados[perfil][c]["cpu"] for c in concs]
        ram = [dados[perfil][c]["ram"] for c in concs]
        ax.plot(concs, cpu, color=AZUL, linewidth=2, marker="o", markersize=8,
                label="CPU da VM")
        ax.plot(concs, ram, color=LARANJA, linewidth=2, marker="s", markersize=8,
                label="memória da VM")
        ax.set_title(titulo, loc="left", fontsize=11, pad=8)
        ax.set_xlabel("clientes concorrentes")
        ax.set_xticks(concs)
        ax.set_xlim(0.6, 4.6)
        ax.set_ylim(0, 100)
        eixo_y_grid(ax)
        ax.legend(frameon=False, loc="upper left", fontsize=9)
    eixos[0].set_ylabel("uso médio durante a janela (%)")
    fig.suptitle("Uso dos recursos provisionados na VM (1 vCPU, 1,9 GB)",
                 x=0.01, ha="left", fontsize=13)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(destino, dpi=160)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summary", default=str(REPO / "results" / "summary.csv"))
    parser.add_argument("--out", default=str(REPO / "docs" / "graficos"))
    args = parser.parse_args()

    dados = carregar(args.summary)
    destino = Path(args.out)
    destino.mkdir(parents=True, exist_ok=True)

    estilo()
    figura_latencia(dados, destino / "latencia.png")
    figura_vazao(dados, destino / "vazao.png")
    figura_uso(dados, destino / "uso-vm.png")
    print("gerado em", destino)


if __name__ == "__main__":
    main()
