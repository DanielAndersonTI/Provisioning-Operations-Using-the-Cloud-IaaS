#!/usr/bin/env bash
# Fase 15 - terceira repeticao contemporanea dos nove cenarios base.
#
# A fase 10 mediu os nove cenarios uma vez, de manha. As fases 12 e 13 mediram
# duas repeticoes a tarde. Como o caminho VDI -> nuvem muda de comportamento ao
# longo do dia (o balanceador e compartilhado e a saida da VDI passa pela rede do
# host), as tres amostras do resumo precisam ser do mesmo periodo. Esta fase
# fecha a terceira amostra e regrava a consolidacao final.
#
# A medicao original continua em results/measurements.csv como historico, mas
# nao entra na media quando existem repeticoes novas do mesmo cenario.

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

size_of() {
    case "$1" in
        cpu) echo 10 ;;
        memory) echo 32 ;;
        io) echo 1024 ;;
    esac
}

section "T12.6 - terceira repeticao dos cenarios base (${DURATION}s)"
for profile in cpu memory io; do
    size="$(size_of "$profile")"
    for concurrency in 1 2 4; do
        run_scenario "T12.6-$profile-c$concurrency-r4" \
            "$profile-c$concurrency-r4" "$profile" "$size" "$concurrency" "$DURATION"
    done
done

section "T12.7 - consolidacao final"
python3 "$BASE/scripts/summarize.py" "$RESULTS" | tee "$LOGS/summarize.log"
evidence_from "T12.7-summary" "python3 scripts/summarize.py results" "$(cat "$LOGS/summarize.log")"

section "Fase 15 concluida"
