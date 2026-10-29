#!/usr/bin/env bash
# Fase 18 - mistura de tamanhos de requisicao (A6)
#
# Todas as matrizes anteriores variam o tamanho do trabalho, mas cada execucao
# usa um unico tamanho: o custo por requisicao e o mesmo em toda a janela. Uma
# carga real nao e assim. Esta fase repete a mesma concorrencia (quatro
# clientes, 20 s) com cada requisicao sorteando o tamanho de uma lista fixa, e
# compara com o cenario de tamanho padrao medido no mesmo dia.
#
# A pergunta que ela responde: a vazao que se ve com um tamanho unico e a mesma
# que se ve com uma mistura cuja media e esse tamanho? Se a resposta for nao, a
# diferenca e o efeito da distribuicao (variancia do trabalho, fila e recusa), e
# nao da media.

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
WARMUP="${WARMUP:-5}"
INTERVAL="${INTERVAL:-0.5}"
REPS="${REPS:-3}"
CONCURRENCY="${CONCURRENCY:-4}"
OUT="$RESULTS/measurements-misto.csv"

size_of() {
    case "$1" in
        cpu) echo 10 ;;
        memory) echo 32 ;;
        io) echo 1024 ;;
    esac
}

# A mistura tem a mesma media do tamanho padrao de cada perfil (5+10+15 = 10,
# 16+32+48 = 32, 512+1024+1536 = 1024), para que a diferenca entre os dois
# cenarios venha da distribuicao e nao do custo medio.
sizes_of() {
    case "$1" in
        cpu) echo "5,10,15" ;;
        memory) echo "16,32,48" ;;
        io) echo "512,1024,1536" ;;
    esac
}

rm -f "$OUT"

section "T16 - mistura de tamanhos, $CONCURRENCY clientes, ${DURATION}s"
for profile in cpu memory io; do
    size="$(size_of "$profile")"
    sizes="$(sizes_of "$profile")"
    for rep in $(seq 1 "$REPS"); do
        run_id="misto-$profile-c$CONCURRENCY-r$rep"
        run_scenario "T16-$run_id" "$run_id" "$profile" "$size" \
            "$CONCURRENCY" "$DURATION" "$sizes" "$OUT"
    done
done

section "Fase 18 concluida"
