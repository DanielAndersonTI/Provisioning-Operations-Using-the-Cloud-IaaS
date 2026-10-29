"""Parse `iostat -dx` output into one CSV row per device.

`iostat` repeats its header for every sample, so the parser keys on the header
line and then accepts any line whose field count matches it. That keeps the
script working whether or not the local sysstat version prints the discard
columns.

Usage:
    python scripts/parse_iostat.py <raw.txt> <run_id> <results/iostat.csv>
"""

import csv
import os
import sys


COLUMNS = ["%util", "aqu-sz", "w/s", "r/s", "w_await", "r_await"]


def blocks(path):
    """Yield (header, linhas) por amostra, so quando a amostra esta completa.

    O bloco e entregue ao final dele, e nao no cabecalho: entregar no cabecalho
    devolveria a lista ainda vazia, porque o consumidor processa o bloco antes
    de o gerador continuar lendo as linhas de dados.
    """
    current = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            parts = line.split()
            if not parts:
                if current and current[1]:
                    yield current
                current = None
                continue
            if parts[0] == "Device":
                if current and current[1]:
                    yield current
                current = (parts, [])
                continue
            if current is None or len(parts) != len(current[0]):
                continue
            if not parts[0].startswith(("vd", "sd", "nvme")):
                continue
            current[1].append(parts)
    if current and current[1]:
        yield current


def number(text):
    try:
        return float(text)
    except ValueError:
        return 0.0


def main():
    raw, run_id, out = sys.argv[1:4]

    per_device = {}
    for header, rows in blocks(raw):
        index = {name: position for position, name in enumerate(header)}
        for parts in rows:
            device = parts[0]
            entry = per_device.setdefault(device, {name: [] for name in COLUMNS})
            for name in COLUMNS:
                if name in index:
                    entry[name].append(number(parts[index[name]]))

    if not per_device:
        print("nenhuma amostra de disco em", raw)
        return

    fields = ["run_id", "device", "samples", "util_mean", "util_max", "aqu_mean",
              "w_s_mean", "r_s_mean", "w_await_mean", "r_await_mean"]
    new = not os.path.exists(out)
    with open(out, "a", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        if new:
            writer.writeheader()
        for device in sorted(per_device):
            entry = per_device[device]
            util = entry["%util"] or [0.0]
            writer.writerow({
                "run_id": run_id,
                "device": device,
                "samples": len(util),
                "util_mean": round(sum(util) / len(util), 2),
                "util_max": round(max(util), 2),
                "aqu_mean": round(sum(entry["aqu-sz"]) / max(len(entry["aqu-sz"]), 1), 3),
                "w_s_mean": round(sum(entry["w/s"]) / max(len(entry["w/s"]), 1), 1),
                "r_s_mean": round(sum(entry["r/s"]) / max(len(entry["r/s"]), 1), 1),
                "w_await_mean": round(sum(entry["w_await"]) / max(len(entry["w_await"]), 1), 2),
                "r_await_mean": round(sum(entry["r_await"]) / max(len(entry["r_await"]), 1), 2),
            })
    print("iostat de", run_id, "resumido em", out)


if __name__ == "__main__":
    main()
