#!/usr/bin/env bash
# Fase 27 - verificação das três aplicações e teste de failover.
#
# A verificação tem três camadas, e cada uma prova uma coisa diferente:
#   1. dentro da VM, nas portas do host — o container responde e o volume
#      recebe escrita;
#   2. pela VIP do balanceador — o caminho externo continua funcionando sem
#      nenhuma mudança no poi-atividades;
#   3. com um container parado — o monitor HTTP marca o membro como ERROR e o
#      balanceador devolve 503; ao subir de novo, o membro volta a ONLINE.
#
# O balanceador é compartilhado pela turma; por isso as leituras de estado usam
# `cap_soft` quando um erro não invalida a conclusão.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/lib4.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

section "T27.1 — verificação local dentro da VM"
cap T27.1-compose-ps "$VM_SSH 'cd $COMPOSE_DIR && sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml ps'"

cap T27.1-smoke-local "$VM_SSH 'a3-smoke'"

cap T27.1-health-json "$VM_SSH 'for p in 8000 8001 8002; do printf \"porta %s: \" \$p; curl -sS -m 10 http://127.0.0.1:\$p/health; echo; done'"

section "T27.2 — verificação pela VIP do balanceador"
cap T27.2-health-vip "for p in 8100:CPU 8101:MEMORY 8102:IO; do port=\${p%%:*}; name=\${p##*:}; printf '%-7s %s ' \"\$name\" \"\$port\"; curl -sS -m 10 -w ' HTTP %{http_code} em %{time_total}s\n' http://$VIP:\$port/health; done"

cap T27.2-work-vip "for p in 8100:10:cpu 8101:32:memory 8102:1024:io; do port=\$(echo \$p | cut -d: -f1); size=\$(echo \$p | cut -d: -f2); echo \"--- \$port /work?size=\$size\"; curl -sS -m 60 -w '\nHTTP %{http_code} em %{time_total}s\n' \"http://$VIP:\$port/work?size=\$size\" | cut -c1-160; echo; done"

cap T27.2-member-status "for pool in pool-app-cpu-daniel-ranya pool-app-memory-daniel-ranya pool-app-io-daniel-ranya; do echo \"== \$pool\"; openstack loadbalancer member list \$pool -c name -c address -c protocol_port -c operating_status; done"

section "T27.3 — failover: parar o container de CPU"
cap T27.3-stop "$VM_SSH 'cd $COMPOSE_DIR && sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml stop cpu; echo; sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml ps'"

echo "aguardando o monitor HTTP detectar a falha (delay 5s x max-retries 3)..."
sleep 45

cap T27.3-member-degraded "openstack loadbalancer member list pool-app-cpu-daniel-ranya -c name -c operating_status; echo; curl -sS -m 10 -o /dev/null -w 'GET /health pela VIP -> HTTP %{http_code}\n' http://$VIP:8100/health || true"

cap T27.3-restore "$VM_SSH 'cd $COMPOSE_DIR && sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml start cpu; sleep 5; sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml ps'"

echo "aguardando o monitor recolocar o membro em serviço..."
sleep 45

cap T27.3-member-restored "openstack loadbalancer member list pool-app-cpu-daniel-ranya -c name -c operating_status; echo; curl -sS -m 10 -w ' HTTP %{http_code} em %{time_total}s\n' http://$VIP:8100/health"

section "Fase 27 concluída"
