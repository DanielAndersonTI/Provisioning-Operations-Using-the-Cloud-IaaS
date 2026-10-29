#!/usr/bin/env bash
# Fase 14d - refazer as evidencias do reanexo com espera.
#
# A fase 14c capturou as evidencias cedo demais: o `systemctl is-active` fica
# verdadeiro assim que a unidade sobe, antes de o socket estar escutando, e o
# balanceador leva cerca de um minuto para marcar o membro como ONLINE de novo.
# Aqui cada verificacao espera a resposta 200 antes de ser registrada.

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

section "T14.11 - espera das tres portas locais"

# Espera a porta responder 200 dentro da VM; ate 60 s.
wait_local() {
    local tries="${1:-30}" p
    for _ in $(seq 1 "$tries"); do
        if $VM_SSH 'for p in 8000 8001 8002; do curl -s -o /dev/null --max-time 3 http://127.0.0.1:$p/health || exit 1; done' 2>/dev/null; then
            return 0
        fi
        sleep 2
    done
    return 1
}
wait_local 30 && echo "as tres portas responderam 200" || echo "alguma porta nao respondeu 200"

cap T14.11-services-start "$VM_SSH 'systemctl is-active app-cpu app-memory app-io; echo; sudo ss -ltnp | grep -E \":800[0-2] \"; echo; for p in 8000 8001 8002; do curl -s -o /dev/null -w \"porta \$p: HTTP %{http_code}\n\" http://127.0.0.1:\$p/health; done'"

cap T14.11-log-write "$VM_SSH 'curl -s -o /dev/null \"http://127.0.0.1:8000/work?size=5\"; sleep 1; echo ultimas linhas do log no volume:; sudo tail -3 $MNT/cpu/app.log; echo; sudo find $MNT -type f -printf \"%p %s bytes\n\" | sort'"

section "T14.11 - conferencia pela VIP (espera o balanceador)"

# O health check do Octavia roda a cada poucos segundos; depois de um restart sao
# necessarias duas falhas/ok para mudar o estado do membro.
wait_vip() {
    local tries="${1:-30}" p codigo
    for _ in $(seq 1 "$tries"); do
        codigo="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$VIP:8100/health" 2>/dev/null)"
        echo "8100/health -> $codigo"
        [ "$codigo" = "200" ] && return 0
        sleep 5
    done
    return 1
}
wait_vip 24 && echo "VIP respondendo 200" || echo "VIP ainda nao respondeu 200"

cap T14.11-vip-health "for p in 8100 8101 8102; do curl -s -o /dev/null -w \"porta \$p: HTTP %{http_code}\n\" --max-time 15 http://$VIP:\$p/health; done; echo; for p in 8100 8101 8102; do curl -s -o /dev/null -w \"porta \$p: HTTP %{http_code}\n\" --max-time 20 \"http://$VIP:\$p/work?size=5\"; done"

section "T14.12 - estado final dos recursos"
cap T14.12-final-state "openstack server show $SERVER -f value -c name -c status -c flavor; echo; openstack volume show $VOLUME -f value -c name -c status -c size; echo; openstack volume snapshot list; echo; openstack image list | grep -E 'snap-vm|snap-vol' || openstack image list | head -10"

section "Fase 14d concluida"
