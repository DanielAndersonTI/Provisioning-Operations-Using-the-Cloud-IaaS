#!/usr/bin/env bash
# Fase 9 - snapshot da VM ja configurada.
#
# `openstack server image create` manda o Nova fotografar o disco raiz da VM e
# guardar o resultado como imagem no Glance. O volume de logs NAO entra no
# snapshot: ele e um volume Cinder separado, com ciclo de vida proprio.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

VM="${VM_NAME:-vm-daniel-ranya}"
SNAP="${SNAP_NAME:-snap-vm-daniel-ranya}"

wait_image_active() {
    local name="$1" tries="${2:-40}" i status
    for i in $(seq 1 "$tries"); do
        status="$(openstack image show "$name" -f value -c status 2>/dev/null || true)"
        [ "$status" = "active" ] && { printf 'active\n'; return 0; }
        sleep 6
    done
    printf '%s\n' "${status:-desconhecido}"
    return 1
}

section "T9.1 - estado da VM antes do snapshot"
cap T9.1-before "openstack server show $VM -c name -c status -c addresses -c flavor -c image -f yaml"

section "T9.2 - criacao do snapshot"
if openstack image show "$SNAP" >/dev/null 2>&1; then
    echo "snapshot $SNAP ja existe"
else
    cap T9.2-snapshot-create "openstack server image create --name $SNAP $VM"
fi
echo "aguardando a imagem ficar active..."
STATUS="$(wait_image_active "$SNAP")"
echo "status final: $STATUS"

section "T9.3 - conferencia do snapshot"
cap T9.3-snapshot-show "openstack image show $SNAP -c id -c name -c status -c size -c disk_format -c min_disk -c properties"
# `-c "Disk Format"` nao funciona aqui: `cap` executa via `bash -lc`, que parte
# o nome da coluna em duas palavras. O `-f yaml` traz todas as colunas sem isso.
cap T9.3-snapshot-list "openstack image list -f yaml"
cap T9.3-server-after "openstack server show $VM -c name -c status"
# O volume continua anexado e intacto: prova de que o snapshot nao o substitui.
cap T9.3-volume-after "openstack volume show ${VOLUME_NAME:-vol-daniel-ranya-logs} -c name -c status -c attachments"

section "Fase 9 concluida"
