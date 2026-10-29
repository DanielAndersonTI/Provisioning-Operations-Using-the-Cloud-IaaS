#!/usr/bin/env bash
# Fase 16 - carga local: o servidor sozinho, sem o balanceador no meio.
#
# As execucoes pela VIP mostram que a demanda para de crescer por volta de 20 a
# 33 requisicoes por segundo e nunca chega a encher as vagas de trabalho: o
# caminho VDI -> balanceador -> VM limita a chegada antes da aplicacao. Para
# observar o limite do proprio servidor (fila e recusa 503), a carga desta fase
# roda DENTRO da VM, contra 127.0.0.1.
#
# Ressalva declarada no relatorio: cliente e servidor dividem o mesmo vCPU, entao
# os numeros absolutos nao servem para comparar com os da VIP - o que se mede
# aqui e o comportamento de admissao (vagas ocupadas, 503, espera).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

VIP="${VIP:-150.165.85.77}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

DURATION="${DURATION:-20}"
CONCURRENCIES="${CONCURRENCIES:-8 32}"

port_of_local() {
    case "$1" in
        cpu) echo 8000 ;;
        memory) echo 8001 ;;
        io) echo 8002 ;;
    esac
}

size_of() {
    case "$1" in
        cpu) echo 10 ;;
        memory) echo 32 ;;
        io) echo 1024 ;;
    esac
}

section "T12.8 - preparo da carga local"
body="$(cat "$BASE/scripts/load_test.py" | $VM_SSH 'sudo tee /opt/atividade3/scripts/load_test.py >/dev/null && sudo chmod 0755 /opt/atividade3/scripts/load_test.py && python3 -m py_compile /opt/atividade3/scripts/load_test.py && echo "sintaxe ok" && wc -l /opt/atividade3/scripts/load_test.py && nproc' 2>&1)"
evidence_from T12.8-local-setup "cat scripts/load_test.py | ssh ... 'sudo tee /opt/atividade3/scripts/load_test.py'" "$body"

rm -f "$RESULTS/measurements-local.csv" "$RESULTS/app-metrics-local.csv"
$VM_SSH 'rm -f /tmp/local.csv' >/dev/null 2>&1 || true

for profile in cpu memory io; do
    port="$(port_of_local "$profile")"
    size="$(size_of "$profile")"
    for concurrency in $CONCURRENCIES; do
        run_id="local-$profile-c$concurrency"
        url="http://127.0.0.1:$port/work?size=$size"

        echo
        echo "=== $run_id  url=$url  concorrencia=$concurrency ==="

        $VM_SSH "curl -s --max-time 10 http://127.0.0.1:$port/metrics" >"/tmp/before-$run_id.json" 2>/dev/null || echo '{}' >"/tmp/before-$run_id.json"

        $VM_SSH "python3 /opt/atividade3/scripts/load_test.py --url '$url' --scenario '$profile' --level $concurrency --concurrency $concurrency --duration $DURATION --run-id $run_id --out /tmp/local.csv" \
            >"$LOGS/local-$run_id.json" 2>&1

        $VM_SSH "curl -s --max-time 10 http://127.0.0.1:$port/metrics" >"/tmp/after-$run_id.json" 2>/dev/null || echo '{}' >"/tmp/after-$run_id.json"
        python3 "$BASE/scripts/app_metrics.py" "/tmp/before-$run_id.json" "/tmp/after-$run_id.json" "$run_id" "$RESULTS/app-metrics-local.csv" >/dev/null 2>&1 || true

        $VM_SSH 'cat /tmp/local.csv' >"$RESULTS/measurements-local.csv" 2>/dev/null || true

        evidence_from "T12.8-$run_id" \
            "ssh ... 'python3 /opt/atividade3/scripts/load_test.py --url $url --concurrency $concurrency --duration $DURATION'" \
            "$(python3 "$BASE/scripts/local_summary.py" "$RESULTS" "$run_id")"
    done
done

section "Fase 16 concluida"
