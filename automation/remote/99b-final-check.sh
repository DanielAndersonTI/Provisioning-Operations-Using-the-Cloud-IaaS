#!/usr/bin/env bash
# Fase 14c - subir as aplicacoes depois do reanexo do volume.
#
# A fase 14b desanexou o volume, tirou o snapshot e reanexou. Os servicos foram
# parados antes da operacao e o comando que os subiria de volta saiu com um erro
# de expansao de `$(seq ...)` dentro da string citada, entao nada subiu. Esta
# fase sobe as unidades, confere o estado local e pela VIP, e regrava as duas
# evidencias que ficaram incompletas.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

VIP="${VIP:-150.165.85.77}"
SERVER="${SERVER:-vm-daniel-ranya}"
VOLUME="${VOLUME:-vol-daniel-ranya-logs}"
MNT="${MNT:-/mnt/atividade3-logs}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

section "T14.11 - subir as aplicacoes e conferir os logs"
cap T14.11-services-start "$VM_SSH 'sudo systemctl start app-cpu app-memory app-io; for i in \$(seq 1 30); do systemctl is-active --quiet app-cpu app-memory app-io && break; sleep 2; done; systemctl is-active app-cpu app-memory app-io; echo; for p in 8000 8001 8002; do curl -s -o /dev/null -w \"porta \$p: HTTP %{http_code}\n\" http://127.0.0.1:\$p/health; done'"

# A escrita de log volta ao volume depois do restart: o drop-in mantem a saida
# no arquivo do volume, e a proxima requisicao produz uma linha nova.
cap T14.11-log-write "$VM_SSH 'curl -s -o /dev/null \"http://127.0.0.1:8000/work?size=5\"; sleep 1; sudo tail -2 $MNT/cpu/app.log; echo; sudo find $MNT -type f -printf \"%p %s bytes\n\" | sort'"

section "T14.11 - conferencia pela VIP"
cap T14.11-vip-health "for p in 8100 8101 8102; do curl -s -o /dev/null -w \"porta \$p: HTTP %{http_code}\n\" --max-time 15 http://$VIP:\$p/health; done; echo; for p in 8100 8101 8102; do curl -s -o /dev/null -w \"porta \$p: HTTP %{http_code}\n\" --max-time 20 \"http://$VIP:\$p/work?size=5\"; done"

section "T14.12 - estado final dos recursos"
cap T14.12-final-state "openstack server show $SERVER -f value -c name -c status -c flavor; echo; openstack volume show $VOLUME -f value -c name -c status -c size; echo; openstack volume snapshot list; echo; openstack image list | grep -E 'snap-vm|snap-vol' || openstack image list | head -10"

section "Fase 14c concluida"
