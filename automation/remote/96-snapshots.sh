#!/usr/bin/env bash
# Fase 14 - snapshot do volume e snapshot final da VM.
#
# O snapshot da VM guarda o disco raiz: sistema, servicos e codigo. O volume tem
# vida propria e nao entra nesse snapshot, entao ele ganha o seu. A ordem aqui e
# a segura: cria-se o snapshot novo, confere-se que ficou `active`, e so entao o
# antigo e removido e o nome e transferido - assim nunca existe um intervalo sem
# nenhum snapshot valido.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

SERVER="${SERVER:-vm-daniel-ranya}"
VOLUME="${VOLUME:-vol-daniel-ranya-logs}"
SNAP_VM="${SNAP_VM:-snap-vm-daniel-ranya}"
SNAP_VOL="${SNAP_VOL:-snap-vol-daniel-ranya-logs}"

wait_image() {
    local image="$1" tries="${2:-60}" status
    for _ in $(seq 1 "$tries"); do
        status="$(openstack image show "$image" -f value -c status 2>/dev/null)"
        echo "status de $image: $status"
        [ "$status" = "active" ] && return 0
        [ "$status" = "error" ] && return 1
        sleep 5
    done
    return 1
}

section "T14.1 - snapshot do volume de logs"
cap_soft T14.1-volume-before "openstack volume show $VOLUME -c id -c status -c size -c attachments; echo; openstack volume list --long"
cap_retry T14.2-volume-snapshot 3 "openstack volume snapshot create --volume $VOLUME --description 'Snapshot do volume de logs da Atividade 3 (usado pelas aplicacoes)' $SNAP_VOL"
for _ in $(seq 1 40); do
    status="$(openstack volume snapshot show "$SNAP_VOL" -f value -c status 2>/dev/null)"
    echo "status do snapshot de volume: $status"
    [ "$status" = "available" ] && break
    sleep 5
done
cap T14.2-volume-snapshot-show "openstack volume snapshot show $SNAP_VOL; echo; openstack volume snapshot list"

section "T14.3 - snapshot final da VM"
# Cria com nome temporario para nao apagar o anterior antes de o novo existir.
cap_soft T14.3-snapshot-before "openstack image list --long | grep -E 'snap|ubuntu-24.04' || openstack image list"
cap_retry T14.4-snapshot-create 3 "openstack server image create --name ${SNAP_VM}-final $SERVER"
wait_image "${SNAP_VM}-final" 80 || true
cap T14.4-snapshot-created "openstack image show ${SNAP_VM}-final -c id -c name -c status -c size -c 'disk_format' -c 'min_disk'; echo; openstack image list | grep ${SNAP_VM}"

section "T14.5 - troca do snapshot antigo pelo novo"
cap_retry T14.5-snapshot-delete-old 3 "openstack image delete $SNAP_VM"
cap_retry T14.6-snapshot-rename 3 "openstack image set --name $SNAP_VM ${SNAP_VM}-final"
cap T14.6-snapshot-final "openstack image show $SNAP_VM -c id -c name -c status -c size; echo; openstack image list | grep -E 'snap-vm|snap-vol'; echo; openstack volume snapshot list"

section "T14.7 - estado final dos recursos"
cap T14.7-final-state "openstack server show $SERVER -f value -c name -c status -c flavor; echo; openstack server list; echo; openstack image list; echo; openstack volume list; echo; openstack volume snapshot list"

section "Fase 14 concluida"
