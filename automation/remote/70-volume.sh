#!/usr/bin/env bash
# Fase 6 - volume de 1 GB anexado a VM e montado de forma persistente.
#
# O cliente Cinder desta nuvem (python-cinderclient em cima do
# python-openstackclient 5.8.0) nao aceita --wait nem em `volume create` nem em
# `server add volume`, por isso a espera e feita consultando o estado do volume.
#
# Para que a montagem sobreviva a reinicializacao, /etc/fstab referencia o UUID
# do sistema de arquivos, e nao o nome do dispositivo.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

VM="${VM_NAME:-vm-daniel-ranya}"
VOL="${VOL_NAME:-vol-daniel-ranya-logs}"
MNT="${VOL_MNT:-/mnt/atividade3-logs}"

KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
VIP="${VIP:-150.165.85.77}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"
vssh() { ssh $SSH_OPTS ubuntu@$VIP "$@"; }

wait_volume_status() {
    local wanted="$1" status attempt
    for attempt in $(seq 1 40); do
        status="$(openstack volume show "$VOL" -f value -c status 2>/dev/null)"
        if [ "$status" = "$wanted" ]; then
            echo "volume em estado '$wanted' apos ${attempt} consulta(s)"
            return 0
        fi
        sleep 5
    done
    echo "volume nao chegou a '$wanted' (estado atual: ${status:-desconhecido})"
    return 1
}

section "T6.1 - criar o volume e anexar a VM"
if openstack volume show "$VOL" >/dev/null 2>&1; then
    echo "volume $VOL ja existe; reaproveitando"
else
    cap T6.1-volume-create "openstack volume create --size 1 --description 'Logs das aplicacoes - Atividade 3' $VOL"
    wait_volume_status available || exit 1
fi

if openstack volume show "$VOL" -f value -c status | grep -q '^in-use$'; then
    echo "volume ja anexado"
else
    cap T6.1-volume-attach "openstack server add volume $VM $VOL"
    wait_volume_status in-use || exit 1
fi

cap T6.1-volume-show "openstack volume show $VOL -c id -c name -c size -c status -c attachments"
cap T6.1-volume-list "openstack volume list"

DEV="$(openstack volume show "$VOL" -f json | jq -r '.attachments[0].device // empty')"
[ -n "$DEV" ] || { echo "nao foi possivel descobrir o dispositivo do volume"; exit 1; }
echo "dispositivo atribuido pela nuvem: $DEV"

section "T6.2 - formatar e montar"
cap T6.2-block-devices "$VM_SSH 'lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT; echo; sudo blkid $DEV 2>/dev/null || echo \"sem sistema de arquivos\"'"

# Formata apenas se o dispositivo ainda nao tiver sistema de arquivos, para que
# repetir a fase nao destrua dados.
cap T6.2-mkfs "$VM_SSH 'if sudo blkid -s TYPE -o value $DEV >/dev/null 2>&1; then echo \"$DEV ja formatado: \$(sudo blkid -s TYPE -o value $DEV)\"; else sudo mkfs.ext4 -L a3logs -m 1 $DEV; fi; echo; sudo blkid $DEV'"

cap T6.2-mount "$VM_SSH 'sudo install -d -o root -g root -m 0755 $MNT; sudo mount LABEL=a3logs $MNT; findmnt $MNT; echo; df -h $MNT; echo; sudo sh -c \"echo volume-ok > $MNT/teste.txt\"; sudo cat $MNT/teste.txt'"

section "T6.3 - montagem persistente por UUID"
# O fstab da imagem e curto e conhecido (root, /boot e /boot/efi); reescrever o
# arquivo inteiro e mais seguro do que tentar remendar linhas quebradas.
cap T6.3-fstab-write "$VM_SSH 'UUID=\$(sudo blkid -s UUID -o value $DEV); sudo cp /etc/fstab /etc/fstab.bak; { echo \"LABEL=cloudimg-rootfs / ext4 discard,commit=30,errors=remount-ro 0 1\"; echo \"LABEL=BOOT /boot ext4 defaults 0 2\"; echo \"LABEL=UEFI /boot/efi vfat umask=0077 0 1\"; echo \"# volume de logs da Atividade 3 (montado por UUID)\"; echo \"UUID=\$UUID $MNT ext4 defaults,nofail 0 2\"; } | sudo tee /etc/fstab; echo; cat /etc/fstab'"

cap T6.3-remount-check "$VM_SSH 'sudo umount $MNT 2>/dev/null; sudo mount -a; findmnt $MNT; echo; sudo cat $MNT/teste.txt; echo; sudo systemctl daemon-reload; systemctl list-units --type=mount --all | grep -i atividade || true'"

section "T6.4 - reiniciar para provar a persistencia da montagem"
cap_soft T6.4-marker "$VM_SSH 'date -u +%FT%TZ | sudo tee $MNT/marca-antes-do-reboot.txt; sudo cat $MNT/marca-antes-do-reboot.txt'"
cap_soft T6.4-reboot "$VM_SSH 'sudo reboot' 2>&1; true"
echo "aguardando a VM voltar..."
sleep 45
ready=1
for attempt in $(seq 1 20); do
    if vssh 'true' 2>/dev/null; then ready=0; echo "VM respondeu na tentativa $attempt"; break; fi
    sleep 10
done
if [ "$ready" -eq 0 ]; then
    cap T6.4-after-reboot "$VM_SSH 'uptime -p; echo; findmnt $MNT; echo; ls -l $MNT; echo; sudo cat $MNT/marca-antes-do-reboot.txt; echo; df -h $MNT; echo; systemctl is-active app-cpu app-memory app-io'"
else
    echo "VM nao voltou a responder"; exit 1
fi

section "Fase 6 concluida"
