#!/usr/bin/env bash
# Fase 1 (continuação) - reconhecimento do Octavia.
#
# O cliente empacotado no Ubuntu 22.04 nao traz o plugin do Octavia, entao
# `openstack loadbalancer` nao existe ate instalar python3-octaviaclient.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

section "T1.4 - cliente do Octavia"
cap T1.4-install-octaviaclient "export DEBIAN_FRONTEND=noninteractive; sudo_run apt-get -o DPkg::Lock::Timeout=180 install -y -qq python3-octaviaclient 2>&1 | tail -5; openstack loadbalancer --help >/dev/null 2>&1 && echo 'plugin ok' || echo 'plugin ausente'"

section "T1.5 - balanceadores do projeto"
cap_soft T1.5-lb-list "openstack loadbalancer list"
cap_soft T1.5-lb-show-poi "openstack loadbalancer show poi-atividades"
cap_soft T1.5-listener-list "openstack loadbalancer listener list"
cap_soft T1.5-pool-list "openstack loadbalancer pool list"
cap_soft T1.5-lb-stats "openstack loadbalancer stats poi-atividades"
cap_soft T1.5-lb-status "openstack loadbalancer status show poi-atividades"

section "T1.6 - portas do balanceador"
cap_soft T1.6-port-list "openstack port list --server poi-atividades 2>/dev/null; openstack port list -c ID -c 'Fixed IP Addresses' -c 'Floating IP Addresses' -c Status | grep -E '10\.5\.8\.242|150\.165\.85\.77' ; true"

section "Fase 1 (Octavia) concluida"
