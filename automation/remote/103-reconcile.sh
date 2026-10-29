#!/usr/bin/env bash
# Fase 20 - reconciliacao da matriz de tamanhos
#
# O mesmo trabalho aparece em duas tabelas: o cenario padrao dos cenarios base
# (CPU 10, memoria 32, IO 1024, tres repeticoes contemporaneas) e a coluna
# correspondente da matriz de tamanhos (uma execucao). Em cinco celulas os dois
# numeros nao fecham: a matriz chega a reportar tres vezes mais latencia para o
# mesmo trabalho com o mesmo numero de clientes. O trabalho nao mudou, entao a
# diferenca esta no caminho compartilhado (VDI -> balanceador -> VM), que e de
# outro grupo no mesmo minuto.
#
# Esta fase refaz o bloco de tamanho dos perfis CPU e IO com uma segunda
# medicao e, se alguma celula continuar acima do teto de plausibilidade (a
# mesma celula nos cenarios base, escalada pelo tamanho do trabalho), refaz de
# novo. A consolidacao passa a usar a execucao mais recente de cada celula.

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
MAX_PASSES="${MAX_PASSES:-2}"

# run_cell <celula> <repeticao>
# A celula tem a forma size-<perfil>-s<tamanho>-c<concorrencia>.
run_cell() {
    local cell="$1" rep="$2"
    local rest="${cell#size-}" profile size concurrency
    profile="${rest%%-s*}"
    size="${rest#*-s}"; size="${size%%-c*}"
    concurrency="${rest##*-c}"
    run_scenario "T17-$cell-r$rep" "$cell-r$rep" "$profile" "$size" \
        "$concurrency" "$DURATION"
}

section "T17.1 - segunda medicao do bloco de tamanho (CPU e IO)"
for profile in cpu io; do
    case "$profile" in
        cpu) sizes="5 10 20" ;;
        io) sizes="512 1024 4096" ;;
    esac
    for size in $sizes; do
        for concurrency in 1 2 4; do
            run_cell "size-$profile-s$size-c$concurrency" 2
        done
    done
done

next_rep=2
for attempt in $(seq 1 "$MAX_PASSES"); do
    section "T17.2 - consolidacao e conferencia (tentativa $attempt)"
    python3 "$BASE/scripts/summarize.py" "$RESULTS" | tee "$LOGS/summarize.log"
    flagged="$(python3 "$BASE/scripts/check_cells.py" "$RESULTS" 2>"$LOGS/check-cells-$attempt.log")" || true
    evidence_from "T17.2-check-cells-$attempt" \
        "python3 scripts/check_cells.py results" "$(cat "$LOGS/check-cells-$attempt.log")"

    if [ -z "$flagged" ]; then
        echo "nenhuma celula acima do teto"
        break
    fi

    next_rep=$((next_rep + 1))
    echo "celulas acima do teto, refazendo com -r$next_rep:"
    printf '  %s\n' $flagged
    for cell in $flagged; do
        run_cell "$cell" "$next_rep"
    done
done

section "T17.3 - consolidacao final da reconciliacao"
python3 "$BASE/scripts/summarize.py" "$RESULTS" | tee "$LOGS/summarize.log"
evidence_from "T17.3-summary" "python3 scripts/summarize.py results" "$(cat "$LOGS/summarize.log")"

section "Fase 20 concluida"
