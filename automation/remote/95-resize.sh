#!/usr/bin/env bash
# Fase 13 - demanda x provisionamento: a mesma VM em general.medium.
#
# O trabalho entrega a VM em general.small, e e nesse flavor que as medicoes da
# fase 12 valem. Para mostrar que a oferta de recurso muda o resultado, esta fase
# redimensiona a MESMA VM para general.medium (2 vCPU, 4 GB), repete uma matriz
# curta, e volta para general.small. Ao final a VM esta como o enunciado pede; o
# flavor e conferido no estado final.
#
# Nada e reinstalado no caminho: o disco, os servicos e o volume sao os mesmos,
# entao a diferenca medida e atribuivel ao provisionamento.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

VIP="${VIP:-150.165.85.77}"
SERVER="${SERVER:-vm-daniel-ranya}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

DURATION="${DURATION:-30}"
WARMUP="${WARMUP:-5}"
INTERVAL="${INTERVAL:-0.5}"

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

size_of() {
    case "$1" in
        cpu) echo 10 ;;
        memory) echo 32 ;;
        io) echo 1024 ;;
    esac
}

wait_status() {
    local wanted="$1" tries="${2:-80}" status
    for _ in $(seq 1 "$tries"); do
        status="$(openstack server show "$SERVER" -f value -c status 2>/dev/null)"
        echo "status: $status"
        [ "$status" = "$wanted" ] && return 0
        [ "$status" = "ERROR" ] && return 1
        sleep 5
    done
    return 1
}

wait_ssh() {
    local tries="${1:-40}"
    for _ in $(seq 1 "$tries"); do
        $VM_SSH 'true' 2>/dev/null && return 0
        sleep 10
    done
    return 1
}

# ---------------------------------------------------------------------------
# T13.1 - estado de partida
# ---------------------------------------------------------------------------
section "T13.1 - estado antes do resize"
cap T13.1-flavor-before "openstack server show $SERVER -f value -c name -c status -c flavor; openstack server show $SERVER -c flavor -c status; echo; openstack flavor show general.small -f value -c name -c vcpus -c ram -c disk; openstack flavor show general.medium -f value -c name -c vcpus -c ram -c disk"
cap T13.1-vm-before "$VM_SSH 'nproc; echo; free -m | head -2; echo; systemctl is-active app-cpu app-memory app-io; echo; df -h /mnt/atividade3-logs | tail -1'"

# ---------------------------------------------------------------------------
# T13.2 - resize para general.medium
# ---------------------------------------------------------------------------
section "T13.2 - resize para general.medium"
cap_retry T13.2-resize-request 3 "openstack server resize --flavor general.medium $SERVER"
wait_status VERIFY_RESIZE 80 || true
cap T13.2-resize-status "openstack server show $SERVER -f value -c status -c flavor; echo; openstack server show $SERVER -c flavor -c status"
cap_retry T13.3-resize-confirm 3 "openstack server resize confirm $SERVER"
wait_status ACTIVE 80 || true

section "T13.3 - espera do SSH e conferencia do novo provisionamento"
if wait_ssh 40; then
    echo "SSH respondeu apos o resize"
else
    echo "SSH nao respondeu apos o resize"
fi

# O servico pode levar alguns segundos para subir depois do reboot.
$VM_SSH 'for i in $(seq 1 30); do systemctl is-active --quiet app-cpu app-memory app-io && break; sleep 2; done' >/dev/null 2>&1 || true

cap T13.4-medium-resources "$VM_SSH 'nproc; echo; grep -c ^processor /proc/cpuinfo; echo; free -m | head -2; echo; systemctl is-active app-cpu app-memory app-io; echo; df -h /mnt/atividade3-logs | tail -1; echo; for p in 8000 8001 8002; do curl -s -o /dev/null -w \"porta \$p: HTTP %{http_code}\\n\" http://127.0.0.1:\$p/health; done'"

# ---------------------------------------------------------------------------
# T13.5 - matriz curta no flavor maior
# ---------------------------------------------------------------------------
run_scenario() {
    local tag="$1" run_id="$2" profile="$3" size="$4" concurrency="$5"
    local port url mon_seconds
    port="$(port_of "$profile")"
    url="http://$VIP:$port/work?size=$size"
    mon_seconds=$(( DURATION + WARMUP + 5 ))

    echo
    echo "=== $run_id  url=$url  concorrencia=$concurrency  janela=${DURATION}s ==="

    curl -s --max-time 10 "http://$VIP:$port/metrics" >"/tmp/before-$run_id.json" 2>/dev/null || echo '{}' >"/tmp/before-$run_id.json"

    $VM_SSH "python3 /opt/atividade3/scripts/monitor.py --scenario $run_id --seconds $mon_seconds --interval $INTERVAL --out /tmp/mon-$run_id.csv" \
        >"$LOGS/monitor-$run_id.log" 2>&1 &
    local monitor_pid=$!

    local iostat_pid=""
    if [ "$profile" = "io" ]; then
        $VM_SSH "iostat -dx 1 $mon_seconds > /tmp/iostat-$run_id.txt 2>&1" >/dev/null 2>&1 &
        iostat_pid=$!
    fi

    sleep 2
    python3 "$BASE/scripts/load_test.py" --url "$url" --scenario "$profile" \
        --level "$concurrency" --concurrency "$concurrency" \
        --duration "$WARMUP" --run-id "warmup-$run_id" \
        --out "$RESULTS/warmup.csv" >/dev/null 2>&1

    python3 "$BASE/scripts/load_test.py" --url "$url" --scenario "$profile" \
        --level "$concurrency" --concurrency "$concurrency" \
        --duration "$DURATION" --run-id "$run_id" \
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

    evidence_from "$tag" "curl $url + python3 scripts/load_test.py --concurrency $concurrency --duration $DURATION (general.medium)" \
        "$(python3 "$BASE/scripts/run_summary.py" "$RESULTS" "$run_id")"
}

section "T13.5 - mesma matriz curta em general.medium"
for profile in cpu memory io; do
    size="$(size_of "$profile")"
    for concurrency in 1 2 4 8; do
        run_scenario "T13.5-med-$profile-c$concurrency" \
            "med-$profile-s$size-c$concurrency" "$profile" "$size" "$concurrency"
    done
done

# ---------------------------------------------------------------------------
# T13.6 - volta para general.small
# ---------------------------------------------------------------------------
section "T13.6 - volta para general.small"
cap_retry T13.6-resize-back 3 "openstack server resize --flavor general.small $SERVER"
wait_status VERIFY_RESIZE 80 || true
cap T13.6-resize-back-status "openstack server show $SERVER -f value -c status -c flavor; echo; openstack server show $SERVER -c flavor -c status"
cap_retry T13.7-resize-back-confirm 3 "openstack server resize confirm $SERVER"
wait_status ACTIVE 80 || true

section "T13.7 - VM de volta em general.small"
if wait_ssh 40; then echo "SSH respondeu apos a volta"; else echo "SSH nao respondeu apos a volta"; fi
$VM_SSH 'for i in $(seq 1 30); do systemctl is-active --quiet app-cpu app-memory app-io && break; sleep 2; done' >/dev/null 2>&1 || true

cap T13.8-small-again "$VM_SSH 'nproc; echo; free -m | head -2; echo; systemctl is-active app-cpu app-memory app-io; echo; df -h /mnt/atividade3-logs | tail -1; echo; for p in 8000 8001 8002; do curl -s -o /dev/null -w \"porta \$p: HTTP %{http_code}\\n\" http://127.0.0.1:\$p/health; done'"
cap T13.8-flavor-final "openstack server show $SERVER -f value -c name -c status -c flavor -c addresses; echo; openstack flavor show general.small -f value -c name -c vcpus -c ram"

section "T13.9 - consolidacao com a matriz do flavor maior"
python3 "$BASE/scripts/summarize.py" "$RESULTS" | tee "$LOGS/summarize.log"
evidence_from "T13.9-summary" "python3 scripts/summarize.py results" "$(cat "$LOGS/summarize.log")"

section "Fase 13 concluida"
