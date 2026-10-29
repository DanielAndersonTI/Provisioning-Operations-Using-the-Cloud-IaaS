#!/usr/bin/env bash
# Fase 14b - snapshot do volume de logs.
#
# O snapshot do volume pela API falhou enquanto ele estava anexado a VM: o
# Cinder desta nuvem recusa `volume snapshot create` com o volume em `in-use`
# ("status must be available"). Este script faz o caminho permitido, e o mais
# conservador:
#
#   1. para as tres aplicacoes, para nao haver escritor durante a operacao;
#   2. desmonta o ponto de montagem e desanexa o volume;
#   3. tira o snapshot e espera ficar `available`;
#   4. reanexa, monta de novo (o fstab ja aponta para o UUID do volume);
#   5. sobe as aplicacoes e confere que os logs anteriores continuam la.
#
# O checksum dos arquivos de log antes e depois prova que a ida e a volta nao
# perderam nada, e serve tambem como demonstracao de que o log vive no volume.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

VIP="${VIP:-150.165.85.77}"
SERVER="${SERVER:-vm-daniel-ranya}"
VOLUME="${VOLUME:-vol-daniel-ranya-logs}"
SNAP_VOL="${SNAP_VOL:-snap-vol-daniel-ranya-logs}"
MNT="${MNT:-/mnt/atividade3-logs}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

wait_volume_status() {
    local wanted="$1" tries="${2:-60}" status
    for _ in $(seq 1 "$tries"); do
        status="$(openstack volume show "$VOLUME" -f value -c status 2>/dev/null)"
        echo "status do volume: $status"
        [ "$status" = "$wanted" ] && return 0
        [ "$status" = "error" ] && return 1
        sleep 5
    done
    return 1
}

wait_snapshot_status() {
    local wanted="$1" tries="${2:-60}" status
    for _ in $(seq 1 "$tries"); do
        status="$(openstack volume snapshot show "$SNAP_VOL" -f value -c status 2>/dev/null)"
        echo "status do snapshot: $status"
        [ "$status" = "$wanted" ] && return 0
        [ "$status" = "error" ] && return 1
        sleep 5
    done
    return 1
}

# ---------------------------------------------------------------------------
# T14.8 - estado do volume com as aplicacoes rodando
# ---------------------------------------------------------------------------
section "T14.8 - preparo: parar escritores e fotografar o volume"
cap_soft T14.8-volume-before "$VM_SSH 'findmnt $MNT; echo; df -h $MNT | tail -1; echo; sudo find $MNT -type f -printf \"%p %s bytes\n\" | sort; echo; sudo sh -c \"cat $MNT/*.log 2>/dev/null | sha256sum\"; echo total_de_linhas:; sudo sh -c \"cat $MNT/*.log 2>/dev/null | wc -l\"'"

section "T14.8 - parar as aplicacoes"
cap T14.8-services-stop "$VM_SSH 'sudo systemctl stop app-cpu app-memory app-io; sleep 2; systemctl is-active app-cpu app-memory app-io; echo; sudo fuser -vm $MNT 2>&1 || echo \"nenhum processo usando $MNT\"'"

# ---------------------------------------------------------------------------
# T14.9 - desmontar e desanexar
# ---------------------------------------------------------------------------
section "T14.9 - desmontar e desanexar o volume"
cap T14.9-umount "$VM_SSH 'sudo umount $MNT; sleep 1; findmnt $MNT || echo \"$MNT desmontado\"; echo; lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT'"
cap_retry T14.9-volume-detach 3 "openstack server remove volume $SERVER $VOLUME"
wait_volume_status available 60 || true
cap T14.9-volume-available "openstack volume show $VOLUME -c id -c name -c size -c status -c attachments; echo; openstack volume list | grep -E 'daniel|ID|Status' || openstack volume list"

# ---------------------------------------------------------------------------
# T14.10 - snapshot do volume
# ---------------------------------------------------------------------------
section "T14.10 - snapshot do volume desanexado"
cap_retry T14.10-volume-snapshot-create 3 "openstack volume snapshot create --volume $VOLUME --description 'Snapshot do volume de logs da Atividade 3' $SNAP_VOL"
wait_snapshot_status available 60 || true
cap T14.10-volume-snapshot-show "openstack volume snapshot show $SNAP_VOL; echo; openstack volume snapshot list"

# ---------------------------------------------------------------------------
# T14.11 - reanexar e remontar
# ---------------------------------------------------------------------------
section "T14.11 - reanexar o volume e remontar"
cap_retry T14.11-volume-attach 3 "openstack server add volume $SERVER $VOLUME"
wait_volume_status in-use 60 || true
cap T14.11-volume-in-use "openstack volume show $VOLUME -c id -c name -c size -c status -c attachments"

# O dispositivo pode demorar alguns segundos para aparecer dentro da VM.
$VM_SSH 'for i in $(seq 1 30); do sudo blkid -L a3logs >/dev/null 2>&1 && break; sleep 2; done' >/dev/null 2>&1 || true
cap T14.11-volume-mount "$VM_SSH 'sudo blkid -L a3logs; echo; sudo mount -a; sleep 1; findmnt $MNT; echo; df -h $MNT | tail -1'"

section "T14.11 - subir as aplicacoes e conferir os logs"
cap T14.11-services-start "$VM_SSH 'sudo systemctl start app-cpu app-memory app-io; for i in \$(seq 1 30); do systemctl is-active --quiet app-cpu app-memory app-io && break; sleep 2; done; systemctl is-active app-cpu app-memory app-io; echo; for p in 8000 8001 8002; do curl -s -o /dev/null -w \"porta \$p: HTTP %{http_code}\n\" http://127.0.0.1:\$p/health; done'"
cap T14.11-logs-intact "$VM_SSH 'sudo find $MNT -type f -printf \"%p %s bytes\n\" | sort; echo; sudo sh -c \"cat $MNT/*.log 2>/dev/null | sha256sum\"; echo total_de_linhas:; sudo sh -c \"cat $MNT/*.log 2>/dev/null | wc -l\"'"

# ---------------------------------------------------------------------------
# T14.12 - estado final
# ---------------------------------------------------------------------------
section "T14.12 - estado final dos recursos"
cap T14.12-final-state "openstack server show $SERVER -f value -c name -c status -c flavor; echo; openstack volume show $VOLUME -f value -c name -c status -c size; echo; openstack volume snapshot list; echo; openstack image list | grep -E 'snap-vm|snap-vol' || openstack image list | head -10"

section "Fase 14b concluida"
