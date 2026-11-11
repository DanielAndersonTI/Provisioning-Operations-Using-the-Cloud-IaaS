#!/usr/bin/env bash
# Fase 28 (continuação) - espera o snapshot ficar active e registra o resultado.
#
# `openstack server image create` retorna antes de o Glance terminar de gravar a
# imagem. A fase 28 espera 4 minutos; quando o disco tem ~19 GB, o qcow2 pode
# levar mais que isso, então esta fase retoma a espera sem criar nada de novo.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/lib4.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

SNAP="${SNAP_NAME_A4:-snap-vm-daniel-ranya-atividade4}"

section "T28.1 - aguardando o snapshot ficar active"
for i in $(seq 1 100); do
    status="$(openstack image show "$SNAP" -f value -c status 2>/dev/null || echo 'desconhecido')"
    [ "$status" = "active" ] && break
    [ $((i % 10)) -eq 0 ] && echo "tentativa $i: status=$status"
    sleep 6
done
echo "status final: $status"

cap T28.1-snapshot-final "openstack image show $SNAP -f yaml"

section "Fase 28 concluída (continuação)"
