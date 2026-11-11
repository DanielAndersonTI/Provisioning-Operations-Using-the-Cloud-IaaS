#!/usr/bin/env bash
# Fase 27.4 - configuração do balanceador poi-atividades.
#
# A fase 27 prova que o caminho externo funciona e que o monitor HTTP reage à
# queda de um container. Esta fase mostra a configuração que sustenta essa
# prova: listener -> pool -> membro -> monitor, cada um lido do OpenStack.
#
# O balanceador é compartilhado pela turma; os comandos são somente leitura.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/lib4.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

section "T27.4 — configuração do balanceador: listener, pool e monitor"

cap T27.4-listeners "for l in app-cpu-daniel-ranya app-memory-daniel-ranya app-io-daniel-ranya; do openstack loadbalancer listener show \$l -c name -c protocol -c protocol_port -c default_pool_id -c operating_status; echo; done"

cap T27.4-pools "for p in pool-app-cpu-daniel-ranya pool-app-memory-daniel-ranya pool-app-io-daniel-ranya; do openstack loadbalancer pool show \$p -c name -c protocol -c lb_algorithm -c healthmonitor_id -c operating_status; echo; done"

cap T27.4-healthmonitors "for p in pool-app-cpu-daniel-ranya pool-app-memory-daniel-ranya pool-app-io-daniel-ranya; do id=\$(openstack loadbalancer pool show \$p -c healthmonitor_id -f value -c healthmonitor_id); openstack loadbalancer healthmonitor show \$id -c name -c type -c url_path -c delay -c timeout -c max_retries -c operating_status; echo; done"

cap T27.4-members "for p in pool-app-cpu-daniel-ranya pool-app-memory-daniel-ranya pool-app-io-daniel-ranya; do openstack loadbalancer member list \$p -c name -c address -c protocol_port -c operating_status -c provisioning_status; echo; done"

section "Fase 27.4 concluída"
