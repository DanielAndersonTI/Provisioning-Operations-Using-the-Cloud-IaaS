#!/usr/bin/env bash
# Fase 21 - segunda medicao das celulas de tamanho padrao do perfil de memoria
#
# A reconciliacao da fase 20 refez os blocos de CPU e de IO, onde o p95 estava
# incompativel com o mesmo trabalho medido nos cenarios base. Nas celulas de
# memoria o p95 bateu, mas a vazao do par com dois clientes (size-memory-s32-c2,
# 12,1 rps) ficou bem abaixo da do cenario base equivalente (16,2 rps). Como essa
# celula e a que fecha a comparacao "matriz de tamanho x cenarios base", ela
# ganha uma segunda medicao - e uma terceira, se o p95 passar do teto.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

VIP="${VIP:-150.165.85.77}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

DURATION="${DURATION:-30}"
WARMUP="${WARMUP:-5}"
INTERVAL="${INTERVAL:-0.5}"

section "T19.1 - segunda medicao do tamanho padrao de memoria"
for concurrency in 1 2 4; do
    run_scenario "T19-size-memory-s32-c$concurrency-r2" \
        "size-memory-s32-c$concurrency-r2" memory 32 "$concurrency" "$DURATION"
done

section "T19.2 - conferencia"
python3 "$BASE/scripts/summarize.py" "$RESULTS" | tee "$LOGS/summarize.log"
flagged="$(python3 "$BASE/scripts/check_cells.py" "$RESULTS" 2>"$LOGS/check-cells-mem.log")" || true
evidence_from T19.2-check-cells "python3 scripts/check_cells.py results" "$(cat "$LOGS/check-cells-mem.log")"

if [ -n "$flagged" ]; then
    echo "celulas acima do teto, refazendo com -r3:"
    printf '  %s\n' $flagged
    for cell in $flagged; do
        rest="${cell#size-}"
        profile="${rest%%-s*}"
        size="${rest#*-s}"; size="${size%%-c*}"
        concurrency="${rest##*-c}"
        run_scenario "T19-$cell-r3" "$cell-r3" "$profile" "$size" "$concurrency" "$DURATION"
    done
    python3 "$BASE/scripts/summarize.py" "$RESULTS" | tee "$LOGS/summarize.log"
fi

section "Fase 21 concluida"
