"""Monta o indice das evidencias: evidencias/manifest.csv.

Uso:
    python scripts/make_manifest.py

Para cada task T<fase>.<n> lista os arquivos que a compoem, o tamanho do texto e
as dimensoes do print. As dimensoes vem do cabecalho PNG, lido direto dos bytes,
para nao depender de Pillow.

O manifesto existe para quem for corrigir: em vez de abrir 200 arquivos, a
tabela diz onde esta cada evidencia e se o print foi renderizado.
"""

import csv
import hashlib
import struct
from pathlib import Path
from collections import defaultdict

REPO = Path(__file__).resolve().parent.parent
EVID = REPO / "evidencias"


def png_size(path):
    """(largura, altura) lidos do bloco IHDR, sem abrir a imagem."""
    with open(path, "rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        return ("", "")
    width, height = struct.unpack(">II", header[16:24])
    return (width, height)


def task_of(name):
    """`T8.2-member-status.txt` -> `T8.2`."""
    stem = Path(name).stem
    return stem.split("-")[0]


def main():
    files = sorted(EVID.iterdir()) if EVID.is_dir() else []
    grupos = defaultdict(lambda: {"txt": [], "png": []})
    for path in files:
        if path.suffix == ".txt":
            grupos[task_of(path.name)]["txt"].append(path)
        elif path.suffix == ".png":
            grupos[task_of(path.name)]["png"].append(path)

    linhas = []
    for task in sorted(grupos, key=lambda t: [int(p) if p.isdigit() else p
                                              for p in t.lstrip("T").replace(".", " ").split()]):
        grupo = grupos[task]
        pares = max(len(grupo["txt"]), len(grupo["png"]), 1)
        for i in range(pares):
            txt = grupo["txt"][i] if i < len(grupo["txt"]) else None
            png = grupo["png"][i] if i < len(grupo["png"]) else None
            largura = altura = ""
            if png is not None:
                largura, altura = png_size(png)
            linhas.append({
                "task": task,
                "texto": txt.name if txt else "",
                "bytes_texto": txt.stat().st_size if txt else "",
                "sha256_texto": (hashlib.sha256(txt.read_bytes()).hexdigest()[:16]
                                 if txt else ""),
                "print": png.name if png else "",
                "largura": largura,
                "altura": altura,
                "bytes_print": png.stat().st_size if png else "",
            })

    destino = EVID / "manifest.csv"
    with open(destino, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=[
            "task", "texto", "bytes_texto", "sha256_texto",
            "print", "largura", "altura", "bytes_print",
        ])
        writer.writeheader()
        writer.writerows(linhas)

    tasks = len(grupos)
    sem_print = sum(1 for linha in linhas if linha["texto"] and not linha["print"])
    print(f"{len(linhas)} linhas, {tasks} tasks, {sem_print} textos sem print")
    print("escrito em", destino)


if __name__ == "__main__":
    main()
