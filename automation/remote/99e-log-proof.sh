#!/usr/bin/env bash
# Fase 14e - evidencia de que o log voltou a ser escrito no volume.
#
# O servidor escreve no log a mensagem de inicializacao e os erros, nao cada
# requisicao. Entao a prova de escrita depois do reanexo nao e "uma requisicao
# gerou linha": e o arquivo do volume ter sido modificado depois do reanexo, com
# a linha de inicializacao do processo que subiu as 17:25:27.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

VIP="${VIP:-150.165.85.77}"
MNT="${MNT:-/mnt/atividade3-logs}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_OPTS="-i $KEY -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

section "T14.11 - escrita no volume depois do reanexo"
cap T14.11-log-write "$VM_SSH 'findmnt $MNT; echo; sudo stat -c \"%n mtime=%y bytes=%s\" $MNT/*/app.log; echo; echo ultima linha de cada log:; sudo sh -c \"for f in $MNT/*/app.log; do echo \\\"-- \\\$f\\\"; tail -1 \\\$f; done\"; echo; sudo sh -c \"cat $MNT/*/app.log | wc -l\"; sudo sh -c \"cat $MNT/*/app.log | sha256sum\"'"

section "T14.11 - estado do balanceador"
cap T14.11-lb-status "openstack loadbalancer status show poi-atividades 2>/dev/null | grep -E 'operating_status|provisioning_status' | sort | uniq -c"

section "Fase 14e concluida"
