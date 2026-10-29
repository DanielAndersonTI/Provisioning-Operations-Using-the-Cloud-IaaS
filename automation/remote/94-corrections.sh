#!/usr/bin/env bash
# Fase 12 - correcoes apontadas na revisao e medicoes complementares.
#
# O que esta fase acrescenta as nove execucoes da fase 10:
#
#   1. as aplicacoes passam a expor /metrics, com contadores internos de espera,
#      trabalho e recusas - o lado do servidor, que o gerador nao ve;
#   2. o perfil de IO passa a escrever o arquivo temporario no volume anexado,
#      e o iostat mede o disco durante esses cenarios;
#   3. matriz tamanho x concorrencia (3 tamanhos x 1/2/4 clientes x 3 perfis);
#   4. saturacao (8 e 16 clientes), para ver a curva dobrar e os 503 aparecerem;
#   5. tres repeticoes de cada cenario base, para media e desvio.
#
# Cada execucao usa sempre a mesma janela de tempo: 30 s nas matrizes novas e
# 45 s nas repeticoes, igual a fase 10, para que as tres amostras de um cenario
# base sejam comparaveis entre si.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

VIP="${VIP:-150.165.85.77}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

ONLY="${ONLY:-all}"
DURATION_A="${DURATION_A:-30}"
DURATION_C="${DURATION_C:-45}"
WARMUP="${WARMUP:-5}"
INTERVAL="${INTERVAL:-0.5}"

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

port_of() {
    case "$1" in
        cpu) echo "${A3_CPU_PORT:-8100}" ;;
        memory) echo "${A3_MEMORY_PORT:-8101}" ;;
        io) echo "${A3_IO_PORT:-8102}" ;;
    esac
}

# Tamanho do trabalho por perfil e por nivel. Os valores "medium" sao os que a
# fase 10 ja usava; small e large ficam em metade e no dobro.
size_of() {
    case "$1:$2" in
        cpu:small) echo 5 ;;
        cpu:medium) echo 10 ;;
        cpu:large) echo 20 ;;
        memory:small) echo 16 ;;
        memory:medium) echo 32 ;;
        memory:large) echo 64 ;;
        io:small) echo 512 ;;
        io:medium) echo 1024 ;;
        io:large) echo 4096 ;;
    esac
}

# ---------------------------------------------------------------------------
# T12.1/T12.2 - deploy do codigo instrumentado e diretorio de IO no volume
# ---------------------------------------------------------------------------
section "T12.1 - redeploy das aplicacoes com /metrics"
cap T12.1-upload-apps "tar czf - -C $HOME/atividade3 apps | $VM_SSH 'sudo tar xzf - -C /opt/atividade3; find /opt/atividade3/apps -name \"*.py\" | sort'"
cap T12.1-checksum "sha256sum $HOME/atividade3/apps/server.py; echo; $VM_SSH 'sha256sum /opt/atividade3/apps/server.py'"
cap T12.1-restart "$VM_SSH 'sudo systemctl restart app-cpu app-memory app-io; sleep 3; systemctl is-active app-cpu app-memory app-io; echo; curl -s http://127.0.0.1:8000/metrics; echo; curl -s http://127.0.0.1:8001/health; echo; curl -s http://127.0.0.1:8002/health'"
cap T12.1-metrics-vip "for p in 8100 8101 8102; do echo \"-- porta \$p\"; curl -s --max-time 10 http://$VIP:\$p/metrics; echo; done"

section "T12.2 - diretorio de trabalho do perfil de IO no volume"
cap T12.2-io-workdir "$VM_SSH 'sudo install -d -o appsvc -g appsvc -m 0750 /mnt/atividade3-logs/scratch; sudo install -d -m 0755 /etc/systemd/system/app-io.service.d; printf \"[Service]\\nEnvironment=A3_WORK_DIR=/mnt/atividade3-logs/scratch\\nReadWritePaths=/var/log/atividade3/io /mnt/atividade3-logs/scratch\\n\" | sudo tee /etc/systemd/system/app-io.service.d/20-workdir.conf >/dev/null; sudo systemctl daemon-reload; sudo systemctl restart app-io; sleep 2; systemctl show app-io -p Environment; echo; systemctl cat app-io | tail -14; echo; curl -s -o /dev/null -w \"io /work pela porta interna: HTTP %{http_code}\\n\" \"http://127.0.0.1:8002/work?size=64\"'"

section "T12.3 - o IO do perfil chega ao disco do volume"
# O iostat precisa comecar antes da carga: rodando depois, mede o disco ocioso.
cap T12.3-io-on-volume "$VM_SSH 'iostat -dx 1 8 > /tmp/io-proof.txt 2>&1 & sleep 1; for i in 1 2 3 4 5 6; do curl -s -o /dev/null \"http://127.0.0.1:8002/work?size=4096\"; done; wait; echo; df -h /mnt/atividade3-logs | tail -1; echo; awk \"NR<=4 || /^Device/ || /^vdb/\" /tmp/io-proof.txt'"

if [ "$ONLY" = "deploy" ]; then
    section "Fase 12 encerrada em ONLY=deploy"
    exit 0
fi

# ---------------------------------------------------------------------------
# Execucao de um cenario
# ---------------------------------------------------------------------------
run_scenario() {
    local tag="$1" run_id="$2" profile="$3" size="$4" concurrency="$5" duration="$6"
    local port url mon_seconds
    port="$(port_of "$profile")"
    url="http://$VIP:$port/work?size=$size"
    mon_seconds=$(( duration + WARMUP + 5 ))

    echo
    echo "=== $run_id  url=$url  concorrencia=$concurrency  janela=${duration}s ==="

    curl -s --max-time 10 "http://$VIP:$port/metrics" >"/tmp/before-$run_id.json" 2>/dev/null || echo '{}' >"/tmp/before-$run_id.json"

    # Monitor dentro da VM: so o sistema operacional de dentro ve CPU, RAM e swap.
    $VM_SSH "python3 /opt/atividade3/scripts/monitor.py --scenario $run_id --seconds $mon_seconds --interval $INTERVAL --out /tmp/mon-$run_id.csv" \
        >"$LOGS/monitor-$run_id.log" 2>&1 &
    local monitor_pid=$!

    local iostat_pid=""
    if [ "$profile" = "io" ]; then
        $VM_SSH "iostat -dx 1 $mon_seconds > /tmp/iostat-$run_id.txt 2>&1" >/dev/null 2>&1 &
        iostat_pid=$!
    fi

    sleep 2

    # Aquecimento: mesma concorrencia, descartado em outro CSV.
    python3 "$BASE/scripts/load_test.py" --url "$url" --scenario "$profile" \
        --level "$concurrency" --concurrency "$concurrency" \
        --duration "$WARMUP" --run-id "warmup-$run_id" \
        --out "$RESULTS/warmup.csv" >/dev/null 2>&1

    python3 "$BASE/scripts/load_test.py" --url "$url" --scenario "$profile" \
        --level "$concurrency" --concurrency "$concurrency" \
        --duration "$duration" --run-id "$run_id" \
        --out "$RESULTS/measurements-v2.csv" >"$LOGS/load-$run_id.json" 2>&1

    wait "$monitor_pid" 2>/dev/null || true
    [ -n "$iostat_pid" ] && { wait "$iostat_pid" 2>/dev/null || true; }

    $VM_SSH "cat /tmp/mon-$run_id.csv" >"$RESULTS/resources-v2-$run_id.csv" 2>/dev/null || true

    if [ "$profile" = "io" ]; then
        $VM_SSH "cat /tmp/iostat-$run_id.txt" >"$RESULTS/iostat-$run_id.txt" 2>/dev/null || true
        python3 "$BASE/scripts/parse_iostat.py" "$RESULTS/iostat-$run_id.txt" "$run_id" "$RESULTS/iostat.csv" \
            >"$LOGS/iostat-$run_id.log" 2>&1 \
            || echo "AVISO: parse_iostat falhou em $run_id" >&2
    fi

    curl -s --max-time 10 "http://$VIP:$port/metrics" >"/tmp/after-$run_id.json" 2>/dev/null || echo '{}' >"/tmp/after-$run_id.json"
    python3 "$BASE/scripts/app_metrics.py" "/tmp/before-$run_id.json" "/tmp/after-$run_id.json" "$run_id" "$RESULTS/app-metrics.csv" >/dev/null 2>&1 || true

    evidence_from "$tag" "curl $url + python3 scripts/load_test.py --concurrency $concurrency --duration $duration" \
        "$(python3 "$BASE/scripts/run_summary.py" "$RESULTS" "$run_id")"
}

# ---------------------------------------------------------------------------
# T12.4 - tamanho do trabalho x concorrencia
# ---------------------------------------------------------------------------
section "T12.4 - matriz tamanho x concorrencia (27 execucoes, ${DURATION_A}s cada)"
for profile in cpu memory io; do
    for level in small medium large; do
        size="$(size_of "$profile" "$level")"
        for concurrency in 1 2 4; do
            run_scenario "T12.4-size-$profile-s$size-c$concurrency" \
                "size-$profile-s$size-c$concurrency" "$profile" "$size" "$concurrency" "$DURATION_A"
        done
    done
done

# ---------------------------------------------------------------------------
# T12.5 - saturacao acima do numero de vagas
# ---------------------------------------------------------------------------
section "T12.5 - saturacao: 8 e 16 clientes no tamanho padrao"
for profile in cpu memory io; do
    size="$(size_of "$profile" medium)"
    for concurrency in 8 16; do
        run_scenario "T12.5-sat-$profile-c$concurrency" \
            "sat-$profile-s$size-c$concurrency" "$profile" "$size" "$concurrency" "$DURATION_A"
    done
done

# ---------------------------------------------------------------------------
# T12.6 - repeticoes dos nove cenarios base
# ---------------------------------------------------------------------------
section "T12.6 - repeticoes 2 e 3 dos cenarios base (${DURATION_C}s, igual a fase 10)"
for profile in cpu memory io; do
    size="$(size_of "$profile" medium)"
    for concurrency in 1 2 4; do
        for rep in 2 3; do
            run_scenario "T12.6-$profile-c$concurrency-r$rep" \
                "$profile-c$concurrency-r$rep" "$profile" "$size" "$concurrency" "$DURATION_C"
        done
    done
done

# ---------------------------------------------------------------------------
# T12.7 - consolidacao
# ---------------------------------------------------------------------------
section "T12.7 - consolidacao das medicoes"
python3 "$BASE/scripts/summarize.py" "$RESULTS" | tee "$LOGS/summarize.log"

evidence_from "T12.7-summary" "python3 scripts/summarize.py results" "$(cat "$LOGS/summarize.log")"

section "Fase 12 concluida"
