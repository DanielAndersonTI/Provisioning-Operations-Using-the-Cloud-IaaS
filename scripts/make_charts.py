"""Gera os graficos do relatorio a partir das tabelas de results/.

Uso:
    python scripts/make_charts.py            # le results/summary.csv
    python scripts/make_charts.py --out docs/graficos

Figuras:
    latencia.png        p50 e p95 por concorrencia, um painel por perfil
    vazao.png           requisicoes por segundo bem-sucedidas, uma linha por perfil
    uso-vm.png          CPU e memoria da VM por concorrencia, um painel por perfil
    tamanho.png         vazao por tamanho do trabalho, uma linha por concorrencia
    saturacao.png       vazao e p95 com 1 a 16 clientes (a vazao achata, a latencia nao)
    flavor.png          general.small contra general.medium, um painel por perfil
    serie-temporal.png  CPU e memoria amostra a amostra em um cenario de cada perfil
    volume.png          ocupacao do disco do volume por tamanho de trabalho (perfil IO)

As cores sao as tres primeiras da paleta categorica validada (azul, laranja,
agua), que passam o teste de daltonismo para todos os pares. Cada figura tem no
maximo tres series por eixo e nenhuma usa dois eixos y.
"""

import argparse
import csv
import re
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
CORES_POR_CONCORRENCIA = {1: AZUL, 2: LARANJA, 4: AGUA}

# Tamanho padrao de cada perfil: e o ponto em que a matriz de tamanho e a de
# saturacao se encontram, e o unico que serve para comparar concorrencias.
TAMANHO_PADRAO = {"cpu": 10, "memory": 32, "io": 1024}


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


def ler_tabela(caminho):
    if not Path(caminho).exists():
        return []
    with open(caminho, encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


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


def por_perfil_tamanho(linhas):
    """perfil -> {concorrencia: {tamanho: linha}}"""
    dados = defaultdict(lambda: defaultdict(dict))
    for linha in linhas:
        dados[linha["profile"]][int(linha["concurrency"])][int(linha["size"])] = linha
    return dados


def figura_tamanho(linhas, destino):
    dados = por_perfil_tamanho(linhas)
    fig, eixos = plt.subplots(1, 3, figsize=(12, 3.8), sharey=True)
    for ax, (perfil, titulo) in zip(eixos, PERFIS):
        concorrencias = sorted(dados[perfil])
        tamanhos = sorted({t for c in concorrencias for t in dados[perfil][c]})
        for conc in concorrencias:
            valores = [float(dados[perfil][conc][t]["success_throughput_rps"])
                       for t in tamanhos if t in dados[perfil][conc]]
            if len(valores) != len(tamanhos):
                continue
            cor = CORES_POR_CONCORRENCIA.get(conc, TINTA_2)
            ax.plot(tamanhos, valores, color=cor, linewidth=2, marker="o",
                    markersize=8, label=f"{conc} cliente" + ("s" if conc > 1 else ""))
            ax.annotate(f"{valores[-1]:.0f}", (tamanhos[-1], valores[-1]),
                        textcoords="offset points", xytext=(8, 0), va="center",
                        fontsize=9, color=cor)
        ax.set_xticks(tamanhos)
        ax.set_xticklabels([str(t) for t in tamanhos])
        ax.set_title(titulo, loc="left", fontsize=11, pad=8)
        ax.set_xlabel("tamanho do trabalho pedido")
        eixo_y_grid(ax)
        ax.legend(frameon=False, loc="upper left", fontsize=9)
    eixos[0].set_ylabel("requisições por segundo (2xx)")
    fig.suptitle("Efeito do tamanho do pedido na vazão", x=0.01, ha="left", fontsize=13)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(destino, dpi=160)
    plt.close(fig)


def figura_saturacao(base, saturacao, destino):
    """Vazao e p95 de 1 a 16 clientes.

    `base` vem de `carregar` (summary.csv, cenarios base com 1, 2 e 4 clientes);
    `saturacao` vem de summary-saturation.csv (8 e 16). A matriz de tamanhos nao
    entra aqui: ela muda o trabalho por requisicao e o ponto de concorrencia
    deixaria de ser comparavel -- foi o que aconteceu na primeira versao deste
    grafico, que mostrava o IO caindo em 4 clientes.
    """
    pontos = defaultdict(dict)
    for perfil, concs in base.items():
        for conc, valores in concs.items():
            pontos[perfil][conc] = (valores["rps"], valores["p95"])
    for linha in saturacao:
        if int(linha["size"]) != TAMANHO_PADRAO[linha["profile"]]:
            continue
        pontos[linha["profile"]][int(linha["concurrency"])] = (
            float(linha["success_throughput_rps"]), float(linha["p95_ms"]))

    # Dois paineis com os dois lados da saturacao: o que a vazao faz e o que a
    # latencia faz. Um painel de taxa de erro seria uma reta no zero -- verdadeira,
    # mas ilegivel; a informacao de que nao houve recusa vai no texto do relatorio.
    fig, eixos = plt.subplots(1, 2, figsize=(11, 4))
    for perfil, titulo in PERFIS:
        concs = sorted(pontos[perfil])
        rps = [pontos[perfil][c][0] for c in concs]
        p95 = [pontos[perfil][c][1] for c in concs]
        cor = CORES_POR_PERFIL[perfil]
        eixos[0].plot(concs, rps, color=cor, linewidth=2, marker="o",
                      markersize=8, label=titulo)
        eixos[1].plot(concs, p95, color=cor, linewidth=2, marker="o",
                      markersize=8, label=titulo)
        eixos[0].annotate(f"{rps[-1]:.0f}", (concs[-1], rps[-1]),
                          textcoords="offset points", xytext=(8, 0), va="center",
                          fontsize=9, color=cor)
        eixos[1].annotate(f"{p95[-1]:,.0f}".replace(",", "."), (concs[-1], p95[-1]),
                          textcoords="offset points", xytext=(8, 0), va="center",
                          fontsize=9, color=cor)
    eixos[0].set_title("Vazão bem-sucedida", loc="left", fontsize=11, pad=8)
    eixos[0].set_ylabel("requisições por segundo (2xx)")
    eixos[1].set_title("Latência p95", loc="left", fontsize=11, pad=8)
    eixos[1].set_ylabel("p95 (ms)")
    for ax in eixos:
        ax.set_xlabel("clientes concorrentes")
        ax.set_xscale("log", base=2)
        ax.set_xticks([1, 2, 4, 8, 16])
        ax.set_xticklabels(["1", "2", "4", "8", "16"])
        ax.set_xlim(0.8, 20)
        eixo_y_grid(ax)
        ax.legend(frameon=False, loc="upper left", fontsize=9)
    fig.suptitle("A vazão achata, a latência não", x=0.01, ha="left", fontsize=13)
    fig.tight_layout(rect=(0, 0, 1, 0.93))
    fig.savefig(destino, dpi=160)
    plt.close(fig)


def figura_flavor(pequeno, medio, destino):
    """general.small contra general.medium, na mesma carga e no tamanho padrao.

    `pequeno` e o dicionario de `carregar` (summary.csv): sao as tres repeticoes
    contemporaneas dos cenarios base, os mesmos numeros da tabela do relatorio.
    `medio` sao as linhas de summary-medium.csv. Usar a matriz de tamanhos como
    lado pequeno daria outra condicao de medicao e o grafico discordaria da
    tabela logo acima dele.
    """
    dados = {"small": defaultdict(dict), "medium": defaultdict(dict)}
    for perfil, concs in pequeno.items():
        for conc, valores in concs.items():
            dados["small"][perfil][conc] = valores["rps"]
    for linha in medio:
        # A comparacao e no tamanho padrao dos dois lados.
        if int(linha["size"]) != TAMANHO_PADRAO[linha["profile"]]:
            continue
        dados["medium"][linha["profile"]][int(linha["concurrency"])] = float(
            linha["success_throughput_rps"])

    fig, eixos = plt.subplots(1, 3, figsize=(12, 3.8), sharey=True)
    for ax, (perfil, titulo) in zip(eixos, PERFIS):
        for chave, cor, rotulo in (("small", AZUL, "general.small (1 vCPU)"),
                                   ("medium", LARANJA, "general.medium (2 vCPU)")):
            pontos = dados[chave][perfil]
            if not pontos:
                continue
            concs = sorted(pontos)
            rps = [pontos[c] for c in concs]
            ax.plot(concs, rps, color=cor, linewidth=2, marker="o", markersize=8,
                    label=rotulo)
            ax.annotate(f"{rps[-1]:.0f}", (concs[-1], rps[-1]),
                        textcoords="offset points", xytext=(8, 0), va="center",
                        fontsize=9, color=cor)
        concs = sorted({c for chave in dados for c in dados[chave][perfil]})
        ax.set_xticks(concs)
        ax.set_title(titulo, loc="left", fontsize=11, pad=8)
        ax.set_xlabel("clientes concorrentes")
        eixo_y_grid(ax)
    eixos[0].set_ylabel("requisições por segundo (2xx)")
    # Legenda única no topo da figura: dentro dos painéis ela cobriria a curva
    # do flavor maior justamente no ponto de pico.
    handles, labels = eixos[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper right", ncol=2, frameon=False, fontsize=9)
    fig.suptitle("Mesma VM, dois provisionamentos", x=0.01, ha="left", fontsize=13)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(destino, dpi=160)
    plt.close(fig)


def figura_volume(linhas, destino):
    """Ocupacao do disco do volume (%util) por concorrencia, uma linha por tamanho.

    So as execucoes da matriz de tamanho entram: sao as unicas com iostat coletado
    lado a lado. O dispositivo vdb e o volume Cinder; o vda e o disco raiz e serve
    de contraste.
    """
    padrao = re.compile(r"^size-io-s(\d+)-c(\d+)$")
    dados = defaultdict(lambda: defaultdict(float))
    for linha in linhas:
        if linha["device"] != "vdb":
            continue
        achado = padrao.match(linha["run_id"])
        if not achado:
            continue
        dados[int(achado.group(1))][int(achado.group(2))] = float(linha["util_mean"])

    if not dados:
        return

    fig, ax = plt.subplots(figsize=(7.2, 4))
    # Os rotulos diretos se sobrepoem quando dois tamanhos terminam com a mesma
    # ocupacao, entao cada serie recebe um deslocamento vertical fixo.
    deslocamentos = [(8, 0), (8, 13), (8, -13)]
    for posicao, tamanho in enumerate(sorted(dados)):
        cor = (AZUL, LARANJA, AGUA)[posicao % 3]
        pontos = dados[tamanho]
        concs = sorted(pontos)
        valores = [pontos[c] for c in concs]
        ax.plot(concs, valores, color=cor, linewidth=2, marker="o", markersize=8,
                label=f"{tamanho} KiB por pedido")
        ax.annotate(f"{valores[-1]:.0f}%", (concs[-1], valores[-1]),
                    textcoords="offset points", xytext=deslocamentos[posicao % 3],
                    va="center", fontsize=9, color=cor)
    ax.set_xlabel("clientes concorrentes")
    ax.set_ylabel("ocupação do disco do volume (%util)")
    ax.set_xticks(sorted({c for pontos in dados.values() for c in pontos}))
    ax.set_ylim(0, 100)
    eixo_y_grid(ax)
    ax.legend(frameon=False, loc="lower right", fontsize=9)
    ax.set_title("O disco do volume sob carga do perfil IO-bound",
                 loc="left", fontsize=13, pad=10)
    fig.tight_layout()
    fig.savefig(destino, dpi=160)
    plt.close(fig)


def figura_serie(resultados, destino):
    cenarios = [("cpu", "cpu-c4-r2"), ("memory", "memory-c4-r2"), ("io", "io-c4-r2")]
    fig, eixos = plt.subplots(1, 3, figsize=(12, 3.8), sharey=True)
    for ax, (perfil, run_id) in zip(eixos, cenarios):
        amostras = ler_tabela(Path(resultados) / f"resources-v2-{run_id}.csv")
        if not amostras:
            continue
        tempo = [i * 0.5 for i in range(len(amostras))]
        cpu = [float(s["cpu_percent"]) for s in amostras]
        ram = [float(s["memory_percent"]) for s in amostras]
        ax.plot(tempo, cpu, color=AZUL, linewidth=2, label="CPU da VM")
        ax.plot(tempo, ram, color=LARANJA, linewidth=2, label="memória da VM")
        ax.set_title(dict(PERFIS)[perfil], loc="left", fontsize=11, pad=8)
        ax.set_xlabel("tempo desde o início da coleta (s)")
        ax.set_ylim(0, 100)
        eixo_y_grid(ax)
        ax.legend(frameon=False, loc="upper left", fontsize=9)
    eixos[0].set_ylabel("uso (%)")
    fig.suptitle("Uso dos recursos durante uma execução de 4 clientes",
                 x=0.01, ha="left", fontsize=13)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(destino, dpi=160)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summary", default=str(REPO / "results" / "summary.csv"))
    parser.add_argument("--out", default=str(REPO / "docs" / "graficos"))
    parser.add_argument("--results", default=str(REPO / "results"))
    args = parser.parse_args()

    dados = carregar(args.summary)
    destino = Path(args.out)
    destino.mkdir(parents=True, exist_ok=True)

    tabela_tamanho = ler_tabela(Path(args.results) / "summary-size.csv")
    tabela_saturacao = ler_tabela(Path(args.results) / "summary-saturation.csv")
    tabela_media = ler_tabela(Path(args.results) / "summary-medium.csv")

    estilo()
    figura_latencia(dados, destino / "latencia.png")
    figura_vazao(dados, destino / "vazao.png")
    figura_uso(dados, destino / "uso-vm.png")
    if tabela_tamanho:
        figura_tamanho(tabela_tamanho, destino / "tamanho.png")
    if dados and tabela_saturacao:
        figura_saturacao(dados, tabela_saturacao, destino / "saturacao.png")
    if dados and tabela_media:
        figura_flavor(dados, tabela_media, destino / "flavor.png")
    figura_serie(args.results, destino / "serie-temporal.png")
    tabela_iostat = ler_tabela(Path(args.results) / "iostat.csv")
    if tabela_iostat:
        figura_volume(tabela_iostat, destino / "volume.png")
    print("gerado em", destino)


if __name__ == "__main__":
    main()
