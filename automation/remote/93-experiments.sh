#!/usr/bin/env bash
# Fase 10 - experimentos de carga nas tres aplicacoes.
#
# Matriz: 3 perfis x 3 niveis de concorrencia (1, 2 e 4) = 9 execucoes, cada uma
# com 5 s de aquecimento descartado e 45 s medidos.
#
# O gerador de carga roda na VDI, fora da VM: latencia vista pelo cliente e a
# unica que inclui conexao TCP, fila no servidor e o retorno pela VIP. O monitor
# roda dentro da VM, porque so o sistema operacional de dentro ve CPU, RAM e
# swap do que foi provisionado.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

VIP="${VIP:-150.165.85.77}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

DURATION="${DURATION:-45}"
WARMUP="${WARMUP:-5}"
INTERVAL="${INTERVAL:-0.5}"
MON_SECONDS=$(( DURATION + WARMUP + 13 ))

# Grava um corpo de texto como evidencia, com o mesmo preambulo de `cap`.
evidence_from() {
    local id="$1" title="$2" body="$3"
    local txt="$EVID/$id.txt"
    {
        printf '$ %s\n' "$title"
        printf '# host=%s user=%s utc=%s\n\n' "$(hostname)" "$(whoami)" "$(utc_now)"
        printf '%s\n' "$body"
        printf '\n[exit 0] %s\n' "$(utc_now)"
    } >"$txt"
    render_png "$txt" "$EVID/$id.png" || true
    echo "----- $id -----"
    printf '%s\n' "$body"
    echo "----------------"
}

section "T10.1 - monitor de recursos dentro da VM"
# Executado direto, sem `cap`, porque a verificacao e o fallback usam aspas
# aninhadas que nao sobreviveriam a uma segunda passada do shell.
if $VM_SSH 'python3 -c "import psutil"' >/dev/null 2>&1; then
    body="$($VM_SSH 'python3 -c "import psutil; print(\"psutil\", psutil.__version__)"' 2>&1)"
else
    body="psutil ausente; instalando python3-psutil pelo apt
$($VM_SSH 'sudo apt-get update -qq && sudo apt-get install -y -qq python3-psutil && python3 -c "import psutil; print(\"psutil\", psutil.__version__)"' 2>&1)"
fi
evidence_from T10.1-psutil "python3 -c 'import psutil'" "$body"

section "T10.2 - envio do monitor para a VM"
body="$(cat "$BASE/scripts/monitor.py" | $VM_SSH 'sudo install -d /opt/atividade3/scripts && sudo tee /opt/atividade3/scripts/monitor.py >/dev/null && sudo python3 -m py_compile /opt/atividade3/scripts/monitor.py && echo "sintaxe ok" && wc -l /opt/atividade3/scripts/monitor.py' 2>&1)"
evidence_from T10.2-monitor-upload "cat scripts/monitor.py | ssh ... 'sudo tee /opt/atividade3/scripts/monitor.py'" "$body"

section "T10.3 - matriz de execucao"
rm -f "$RESULTS/measurements.csv" "$RESULTS/warmup.csv"
mkdir -p "$LOGS"

size_of() {
    case "$1" in
        cpu) echo 10 ;;
        memory) echo 32 ;;
        io) echo 1024 ;;
    esac
}
port_of() {
    case "$1" in
        cpu) echo "${A3_CPU_PORT:-8100}" ;;
        memory) echo "${A3_MEMORY_PORT:-8101}" ;;
        io) echo "${A3_IO_PORT:-8102}" ;;
    esac
}

for profile in cpu memory io; do
    port="$(port_of "$profile")"
    size="$(size_of "$profile")"
    url="http://$VIP:$port/work?size=$size"
    for concurrency in 1 2 4; do
        scenario="$profile-c$concurrency"
        echo
        echo "=== $scenario  url=$url  concorrencia=$concurrency ==="

        # Monitor dentro da VM, em segundo plano, cobrindo aquecimento + medicao.
        $VM_SSH "python3 /opt/atividade3/scripts/monitor.py --scenario $scenario --seconds $MON_SECONDS --interval $INTERVAL --out /tmp/mon-$scenario.csv" \
            >"$LOGS/monitor-$scenario.log" 2>&1 &
        monitor_pid=$!
        sleep 2

        # Aquecimento: mesma concorrencia, resultado descartado em outro CSV.
        python3 "$BASE/scripts/load_test.py" --url "$url" --scenario "$scenario" \
            --level "$concurrency" --concurrency "$concurrency" \
            --duration "$WARMUP" --run-id "warmup-$scenario" \
            --out "$RESULTS/warmup.csv" >/dev/null 2>&1

        # Medicao.
        python3 "$BASE/scripts/load_test.py" --url "$url" --scenario "$scenario" \
            --level "$concurrency" --concurrency "$concurrency" \
            --duration "$DURATION" --run-id "$scenario" \
            --out "$RESULTS/measurements.csv" >"$LOGS/load-$scenario.json" 2>&1

        wait "$monitor_pid" || true
        $VM_SSH "cat /tmp/mon-$scenario.csv" >"$RESULTS/resources-$scenario.csv" 2>/dev/null || true

        evidence_from "T10.3-$scenario" \
            "python3 scripts/load_test.py --url $url --concurrency $concurrency --duration $DURATION" \
            "$(python3 - "$RESULTS/measurements.csv" "$RESULTS/resources-$scenario.csv" "$scenario" <<'PY'
import csv, statistics, sys

measurements, resources, scenario = sys.argv[1:4]
row = None
with open(measurements, encoding="utf-8", newline="") as handle:
    for item in csv.DictReader(handle):
        if item["run_id"] == scenario:
            row = item
if row is None:
    print("execucao nao encontrada em", measurements)
    raise SystemExit(0)

print("aplicacao        :", row["scenario"])
print("url              :", row["url"])
print("concorrencia     :", row["concurrency"], "cliente(s)")
print("janela medida    :", row["duration_target_s"], "s (mais aquecimento descartado)")
print()
print("requisicoes      :", row["attempts"])
print("sucessos         :", row["successes"])
print("erros            :", row["errors"], row["errors_by_kind"] or "")
print("taxa de erro     :", row["error_rate"])
print("vazao (rps)      :", row["success_throughput_rps"], "(sucesso) /",
      row["throughput_rps"], "(total)")
print("latencia media   :", row["mean_ms"], "ms")
print("latencia p50/p95 :", row["p50_ms"], "/", row["p95_ms"], "ms")
print("latencia p99/max :", row["p99_ms"], "/", row["max_ms"], "ms")

try:
    with open(resources, encoding="utf-8", newline="") as handle:
        samples = list(csv.DictReader(handle))
except FileNotFoundError:
    samples = []

if samples:
    cpu = [float(s["cpu_percent"]) for s in samples]
    mem = [float(s["memory_percent"]) for s in samples]
    swap = [float(s["swap_used_mb"]) for s in samples]
    print()
    print("amostras do monitor:", len(samples), "(intervalo de 0,5 s)")
    print(f"cpu da VM        : media {statistics.mean(cpu):5.1f}%  pico {max(cpu):5.1f}%")
    print(f"memoria da VM    : media {statistics.mean(mem):5.1f}%  pico {max(mem):5.1f}%")
    print(f"swap em uso      : media {statistics.mean(swap):5.1f} MiB pico {max(swap):5.1f} MiB")
PY
)"
    done
done

section "T10.4 - consolidacao"
python3 - "$RESULTS" <<'PY'
import csv, os, statistics, sys

results = sys.argv[1]
rows = list(csv.DictReader(open(os.path.join(results, "measurements.csv"), encoding="utf-8", newline="")))

fields = [
    "scenario", "profile", "concurrency", "attempts", "successes", "errors",
    "error_rate", "throughput_rps", "success_throughput_rps",
    "mean_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms",
    "cpu_mean", "cpu_max", "mem_mean", "mem_max", "swap_max",
]
out = []
for row in rows:
    samples = []
    path = os.path.join(results, f"resources-{row['run_id']}.csv")
    if os.path.exists(path):
        samples = list(csv.DictReader(open(path, encoding="utf-8", newline="")))
    cpu = [float(s["cpu_percent"]) for s in samples] or [0.0]
    mem = [float(s["memory_percent"]) for s in samples] or [0.0]
    swap = [float(s["swap_used_mb"]) for s in samples] or [0.0]
    out.append({
        "scenario": row["run_id"],
        "profile": row["scenario"],
        "concurrency": row["concurrency"],
        "attempts": row["attempts"],
        "successes": row["successes"],
        "errors": row["errors"],
        "error_rate": row["error_rate"],
        "throughput_rps": row["throughput_rps"],
        "success_throughput_rps": row["success_throughput_rps"],
        "mean_ms": row["mean_ms"],
        "p50_ms": row["p50_ms"],
        "p95_ms": row["p95_ms"],
        "p99_ms": row["p99_ms"],
        "max_ms": row["max_ms"],
        "cpu_mean": round(statistics.mean(cpu), 1),
        "cpu_max": round(max(cpu), 1),
        "mem_mean": round(statistics.mean(mem), 1),
        "mem_max": round(max(mem), 1),
        "swap_max": round(max(swap), 1),
    })

with open(os.path.join(results, "summary.csv"), "w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields)
    writer.writeheader()
    writer.writerows(out)

header = f"{'cenario':<10}{'conc':>5}{'req':>7}{'ok':>7}{'erro':>6}{'rps':>9}{'med_ms':>9}{'p95_ms':>9}{'cpu%':>7}{'ram%':>7}"
print(header)
print("-" * len(header))
for item in out:
    print(f"{item['scenario']:<10}{item['concurrency']:>5}{item['attempts']:>7}"
          f"{item['successes']:>7}{item['errors']:>6}"
          f"{item['success_throughput_rps']:>9}{item['mean_ms']:>9}"
          f"{item['p95_ms']:>9}{item['cpu_mean']:>7}{item['mem_mean']:>7}")
PY

section "Fase 10 concluida"
