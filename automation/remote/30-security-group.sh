#!/usr/bin/env bash
# Fase 3a - grupo de seguranca da VM.
#
# A VM fica na rede `provider` (10.5.8.0/22) e nao tem IP publico: quem fala
# com ela e o balanceador, que tambem esta nessa sub-rede. Por isso as regras
# liberam as portas apenas a partir desse CIDR, e nao da internet inteira.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

SG="${SG_NAME:-sg-daniel-ranya}"
NET_CIDR="${NET_CIDR:-10.5.8.0/22}"

section "T3.1 - grupo de seguranca"
cap_soft T3.1-sg-create "openstack security group create $SG --description 'Acesso do balanceador a VM - Atividade 3 POI' 2>&1"

cap_soft T3.1-rule-ssh   "openstack security group rule create --protocol tcp --dst-port 22 --remote-ip $NET_CIDR $SG 2>&1"
cap_soft T3.1-rule-apps  "openstack security group rule create --protocol tcp --dst-port 8000:8002 --remote-ip $NET_CIDR $SG 2>&1"
cap_soft T3.1-rule-icmp  "openstack security group rule create --protocol icmp --remote-ip $NET_CIDR $SG 2>&1"

cap T3.1-sg-show "openstack security group show $SG"
cap T3.1-sg-rules "openstack security group rule list $SG"

section "Fase 3a concluida"
