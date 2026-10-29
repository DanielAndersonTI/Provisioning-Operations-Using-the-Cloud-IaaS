#!/usr/bin/env bash
# Fase 4 - acesso SSH pela VIP do balanceador.
#
# A VM nao tem IP publico. O acesso externo passa pelo balanceador
# `poi-atividades`, que e compartilhado entre os grupos: cada grupo usa portas
# proprias. Para este grupo: TCP 2222 na VIP -> 10.5.9.15:22 na VM.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

VM="${VM_NAME:-vm-daniel-ranya}"
VM_IP="${VM_IP:-10.5.9.15}"
SUBNET_ID="${SUBNET_ID:-17de9c72-e5dc-4da0-ae0a-013f7e42400e}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
LB=poi-atividades
VIP=150.165.85.77
SSH_PORT="${SSH_PORT:-2222}"

section "T4.1 - listener TCP para SSH"
cap_soft T4.1-listener-create "openstack loadbalancer listener create --name ssh-daniel-ranya --protocol TCP --protocol-port $SSH_PORT $LB --wait 2>&1"
cap_soft T4.1-pool-create "openstack loadbalancer pool create --name pool-ssh-daniel-ranya --lb-algorithm ROUND_ROBIN --listener ssh-daniel-ranya --protocol TCP --wait 2>&1"
cap_soft T4.1-hm-create "openstack loadbalancer healthmonitor create --name hm-ssh-daniel-ranya --delay 5 --timeout 4 --max-retries 3 --type TCP pool-ssh-daniel-ranya --wait 2>&1"
cap_soft T4.1-member-create "openstack loadbalancer member create --name $VM --subnet-id $SUBNET_ID --address $VM_IP --protocol-port 22 pool-ssh-daniel-ranya --wait 2>&1"

cap T4.1-listener-show "openstack loadbalancer listener show ssh-daniel-ranya"
cap T4.1-pool-status "openstack loadbalancer pool show pool-ssh-daniel-ranya -c name -c operating_status -c provisioning_status; openstack loadbalancer member list pool-ssh-daniel-ranya"

section "T4.2 - teste de acesso SSH pela VIP"
# O listener leva alguns segundos para ficar ONLINE depois de criado; tenta
# algumas vezes antes de declarar falha.
SSH_CMD="ssh -i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o BatchMode=yes ubuntu@$VIP 'hostname; uname -a; head -2 /etc/os-release'"
OUT="$EVID/T4.2-ssh-vip.txt"
{
    printf '$ %s\n# host=%s utc=%s\n\n' "$SSH_CMD" "$(hostname)" "$(utc_now)"
} > "$OUT"
RC=1
for attempt in 1 2 3 4 5 6 7 8; do
    echo "tentativa $attempt..." | tee -a "$OUT"
    if eval "$SSH_CMD" >>"$OUT" 2>&1; then
        RC=0
        break
    fi
    sleep 15
done
printf '\n[exit %s] %s\n' "$RC" "$(utc_now)" >>"$OUT"
render_png "$OUT" "$EVID/T4.2-ssh-vip.png" || true
echo "----- T4.2-ssh-vip (exit $RC) -----"
cat "$OUT"
echo "--------------------------"

section "Fase 4 concluida"
