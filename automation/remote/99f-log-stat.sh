#!/usr/bin/env bash
# Fase 14f - refazer a evidencia do log, sem glob em laco no shell local.
#
# A primeira versao usava um laco com `$f` dentro de uma string entre aspas
# duplas: o shell local expandia a variavel antes de enviar o comando e, com
# `set -u`, o script abortava. Aqui os caminhos vao explicitos e a unica
# expansao que roda como root e a do `sh -c`, com o padrao entre aspas duplas
# (que o shell remoto nao expande antes de entregar ao sudo).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

MNT="${MNT:-/mnt/atividade3-logs}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_OPTS="-i $KEY -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@150.165.85.77"

section "T14.11 - escritas no volume depois do reanexo"
cap T14.11-log-write "$VM_SSH 'findmnt $MNT; echo; sudo find $MNT -maxdepth 2 -name app.log -printf \"%p mtime=%TY-%Tm-%TdT%TH:%TM:%TS bytes=%s\n\" | sort; echo; echo ultima linha de cada log:; sudo tail -1 $MNT/cpu/app.log; sudo tail -1 $MNT/memory/app.log; sudo tail -1 $MNT/io/app.log; echo; sudo sh -c \"cat $MNT/*/app.log | wc -l\"; sudo sh -c \"cat $MNT/*/app.log | sha256sum\"'"

section "Fase 14f concluida"
