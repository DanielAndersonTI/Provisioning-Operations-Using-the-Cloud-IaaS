#!/usr/bin/env bash
# Fase 19 - repeticoes dos tres cenarios que estavam com uma execucao so
#
# As matrizes de tamanho e de saturacao tinham uma medicao por celula, enquanto
# os cenarios base tinham tres. Uma celula unica nao permite distinguir um
# efeito de uma noite ruim do caminho compartilhado. Esta fase repete as tres
# celulas mais citadas no relatorio (CPU s20 com quatro clientes, IO saturado
# com dezesseis, memoria saturada com dezesseis) duas vezes cada.
#
# As repeticoes entram em measurements-v2.csv com o sufixo -r2 e -r3; a
# consolidacao usa a mais recente por celula, como nas demais matrizes.

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

section "T18 - repeticoes (${DURATION}s cada)"
for cell in "size-cpu-s20-c4" "sat-io-s1024-c16" "sat-memory-s32-c16"; do
    rest="${cell#size-}"
    rest="${rest#sat-}"
    profile="${rest%%-s*}"
    size="${rest#*-s}"; size="${size%%-c*}"
    concurrency="${rest##*-c}"

    for rep in 2 3; do
        run_scenario "T18-$cell-r$rep" "$cell-r$rep" "$profile" "$size" \
            "$concurrency" "$DURATION"
    done
done

section "Fase 19 concluida"
