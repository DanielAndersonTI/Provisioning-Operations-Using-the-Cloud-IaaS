#!/usr/bin/env bash
# Fase 28 - snapshot da VM no estado conteinerizado.
#
# O snapshot da Atividade 3 (snap-vm-daniel-ranya) permanece intacto e continua
# sendo o estado anterior ao Docker. Este segundo snapshot guarda a VM já com o
# Docker instalado e os containers em execução, que é o estado entregue na
# Atividade 4. O volume de logs não entra no snapshot: é um volume Cinder com
# ciclo de vida próprio.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/lib4.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

VM="${VM_NAME:-vm-daniel-ranya}"
SNAP="${SNAP_NAME_A4:-snap-vm-daniel-ranya-atividade4}"

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

section "T28.1 — estado da VM antes do snapshot"
cap T28.1-before "openstack server show $VM -c name -c status -c addresses -c flavor -c image -f yaml"
cap T28.1-containers "$VM_SSH 'cd $COMPOSE_DIR && sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml ps'"

section "T28.1 — criação do snapshot"
if openstack image show "$SNAP" >/dev/null 2>&1; then
    echo "snapshot $SNAP já existe"
else
    cap T28.1-snapshot-create "openstack server image create --name $SNAP $VM"
fi
echo "aguardando a imagem ficar active..."
STATUS="$(wait_image_active "$SNAP")"
echo "status final: $STATUS"

section "T28.1 — conferência do snapshot"
cap T28.1-snapshot-show "openstack image show $SNAP -c id -c name -c status -c size -c disk_format -c min_disk"
cap T28.1-snapshot-list "openstack image list -f yaml"
cap T28.1-server-after "openstack server show $VM -c name -c status"
cap T28.1-volume-after "openstack volume show ${VOLUME_NAME:-vol-daniel-ranya-logs} -c name -c status -c attachments"

section "Fase 28 concluída"
