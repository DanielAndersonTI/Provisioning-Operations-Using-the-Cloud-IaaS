#!/usr/bin/env bash
# Fase 1 — reconhecimento da nuvem (Primeira parte, item 2).
#
# Lista tudo o que a atividade manda listar antes de criar qualquer recurso.
# Duas listas merecem atenção especial: flavors (para confirmar se
# `general.small` existe) e load balancers (para saber se `poi-atividades`
# já existe e não criar um duplicado).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

section "T1.1 — entidades exigidas pelo material"
cap T1.1-flavor-list "openstack flavor list"
cap T1.1-server-list "openstack server list --all-projects 2>/dev/null || openstack server list"
cap T1.1-image-list "openstack image list"
cap T1.1-snapshot-list "openstack image list --property image_type=snapshot 2>/dev/null || openstack image list --long | grep -i snapshot; true"

section "T1.2 — entidades de apoio"
cap T1.2-network-list "openstack network list"
cap T1.2-subnet-list "openstack subnet list"
cap T1.2-security-group-list "openstack security group list"
cap T1.2-volume-list "openstack volume list"
cap T1.2-loadbalancer-list "openstack loadbalancer list"
cap T1.2-floating-ip-list "openstack floating ip list"
cap T1.2-keypair-list "openstack keypair list"
cap T1.2-quota-show "openstack quota show"

section "T1.3 — checagens de decisão"
cap_soft T1.3-flavor-general-small "openstack flavor show general.small 2>&1"
cap_soft T1.3-flavor-names "openstack flavor list -f value -c Name | sort"
cap_soft T1.3-lb-poi "openstack loadbalancer show poi-atividades 2>&1"

section "Fase 1 concluída"
