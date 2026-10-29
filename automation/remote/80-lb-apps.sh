#!/usr/bin/env bash
# Fase 8 - as tres aplicacoes publicadas no balanceador.
#
# Cada aplicacao ganha um listener HTTP proprio na VIP (portas 8100-8102), um
# pool com um membro (a VM, nas portas 8000-8002) e um monitor HTTP em /health.
# A VIP e compartilhada por todos os grupos da disciplina, por isso as portas
# externas nao coincidem com as internas.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

LB=poi-atividades
VIP="${VIP:-150.165.85.77}"
VM_IP="${VM_IP:-10.5.9.15}"
SUBNET_ID="${SUBNET_ID:-17de9c72-e5dc-4da0-ae0a-013f7e42400e}"
VM="${VM_NAME:-vm-daniel-ranya}"

KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

section "T8.1 - estado atual da VIP"
cap T8.1-listener-list "openstack loadbalancer listener list -c name -c protocol -c protocol_port"

section "T8.2 - listeners, pools, monitores e membros"
# perfil:porta_externa:porta_interna
for spec in cpu:8100:8000 memory:8101:8001 io:8102:8002; do
    profile="${spec%%:*}"
    rest="${spec#*:}"
    ext="${rest%%:*}"
    int="${rest##*:}"
    listener="app-$profile-daniel-ranya"
    pool="pool-app-$profile-daniel-ranya"

    if openstack loadbalancer listener show "$listener" >/dev/null 2>&1; then
        echo "listener $listener ja existe"
    else
        cap_retry "T8.2-listener-$profile" 10 "openstack loadbalancer listener create --name $listener --protocol HTTP --protocol-port $ext $LB"
    fi

    if openstack loadbalancer pool show "$pool" >/dev/null 2>&1; then
        echo "pool $pool ja existe"
    else
        cap_retry "T8.2-pool-$profile" 10 "openstack loadbalancer pool create --name $pool --lb-algorithm ROUND_ROBIN --listener $listener --protocol HTTP"
    fi

    # O monitor e consultado pelo NOME dele, nao pelo nome do pool: `healthmonitor
    # show` recebe id ou nome de monitor.
    if openstack loadbalancer healthmonitor show "hm-app-$profile-daniel-ranya" >/dev/null 2>&1; then
        echo "health monitor de $pool ja existe"
    else
        cap_retry "T8.2-hm-$profile" 10 "openstack loadbalancer healthmonitor create --name hm-app-$profile-daniel-ranya --delay 5 --timeout 4 --max-retries 3 --type HTTP --url-path /health --expected-codes 200 $pool"
    fi

    # `-f value` separa as colunas por espaco, nao por virgula.
    if openstack loadbalancer member list "$pool" -c address -c protocol_port -f value 2>/dev/null | grep -qx "$VM_IP $int"; then
        echo "membro $VM_IP:$int ja existe em $pool"
    else
        cap_retry "T8.2-member-$profile" 10 "openstack loadbalancer member create --name $VM --subnet-id $SUBNET_ID --address $VM_IP --protocol-port $int $pool"
    fi
done

sleep 15
cap T8.2-status "openstack loadbalancer listener list -c name -c protocol -c protocol_port; echo; openstack loadbalancer pool list -c name -c provisioning_status -c operating_status; echo; openstack loadbalancer healthmonitor list -c name -c type -c url_path -c operating_status"
cap T8.2-member-status "for pool in pool-app-cpu-daniel-ranya pool-app-memory-daniel-ranya pool-app-io-daniel-ranya; do echo \"== \$pool\"; openstack loadbalancer member list \$pool -c name -c address -c protocol_port -c operating_status; done"

section "T8.3 - teste externo pela VIP"
cap T8.3-health-vip "for p in 8100:CPU 8101:MEMORY 8102:IO; do port=\${p%%:*}; name=\${p##*:}; printf '%-7s %s ' \"\$name\" \"\$port\"; curl -sS -m 10 -w ' HTTP %{http_code} em %{time_total}s\n' http://$VIP:\$port/health; done"
cap T8.3-work-vip "for p in 8100:10:cpu 8101:32:memory 8102:1024:io; do port=\$(echo \$p | cut -d: -f1); size=\$(echo \$p | cut -d: -f2); echo \"--- \$port /work?size=\$size\"; curl -sS -m 60 -w '\nHTTP %{http_code} em %{time_total}s\n' \"http://$VIP:\$port/work?size=\$size\" | cut -c1-160; echo; done"
cap T8.3-smoke-vip "$VM_SSH 'A3_HOST=$VIP A3_CPU_PORT=8100 A3_MEMORY_PORT=8101 A3_IO_PORT=8102 a3-smoke'"

section "T8.4 - health check e comportamento em falha"
cap T8.4-stop-app "$VM_SSH 'sudo systemctl stop app-cpu; systemctl is-active app-cpu; echo \"aplicacao parada; o monitor deve marcar o membro como indisponivel\"'"
echo "aguardando o monitor HTTP detectar a falha (delay 5s x max-retries 3)..."
sleep 45
cap T8.4-member-degraded "openstack loadbalancer member list pool-app-cpu-daniel-ranya -c name -c operating_status; echo; curl -sS -m 10 -o /dev/null -w 'GET /health pela VIP -> HTTP %{http_code}\n' http://$VIP:8100/health || true"
cap T8.4-restore "$VM_SSH 'sudo systemctl start app-cpu; sleep 3; systemctl is-active app-cpu'"
echo "aguardando o monitor recolocar o membro em servico..."
sleep 45
cap T8.4-member-restored "openstack loadbalancer member list pool-app-cpu-daniel-ranya -c name -c operating_status; echo; curl -sS -m 10 -w ' HTTP %{http_code} em %{time_total}s\n' http://$VIP:8100/health"

section "Fase 8 concluida"
