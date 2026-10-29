#!/usr/bin/env bash
# Fase 3b - criacao da VM da atividade.
#
# Uma unica VM por grupo: flavor general.small (1 vCPU, 2 GB, disco 20 GB) e
# imagem ubuntu-24.04, na rede `provider`, com a chave e o grupo de seguranca
# criados nas fases anteriores.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

VM="${VM_NAME:-vm-daniel-ranya}"
KEY_NAME="${KEY_NAME:-atividade3-daniel-ranya}"
SG="${SG_NAME:-sg-daniel-ranya}"
FLAVOR="${FLAVOR_NAME:-general.small}"
IMAGE="${IMAGE_NAME:-ubuntu-24.04}"
NET="${NETWORK_NAME:-provider}"

section "T3.2 - criacao da VM"
cap T3.2-server-create "openstack server create --flavor $FLAVOR --image $IMAGE --key-name $KEY_NAME --network $NET --security-group $SG $VM --wait"
cap T3.2-server-show "openstack server show $VM"
cap T3.2-server-address "openstack server show $VM -f value -c addresses"
cap T3.2-server-list "openstack server list --name $VM"

section "Fase 3b concluida"
