#!/usr/bin/env bash
# Fase 7 - logs das aplicacoes no volume e rotacao.
#
# Os servicos passam a escrever a saida em /mnt/atividade3-logs/<perfil>/, que e
# o volume de 1 GB criado na fase 6. Um drop-in em cada unidade sobrescreve
# apenas StandardOutput/StandardError, sem duplicar o restante do arquivo.
#
# A rotacao usa copytruncate: o systemd mantem o descritor aberto, entao renomear
# o arquivo faria o processo continuar escrevendo no arquivo ja rotacionado. A
# diretiva `su` nao e usada de proposito: o systemd cria app.log como root e o
# logrotate precisa de root para abri-lo.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
VIP="${VIP:-150.165.85.77}"
SSH_PORT="${SSH_PORT:-2222}"
MNT="${VOL_MNT:-/mnt/atividade3-logs}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

PAYLOAD="$HOME/atividade3/payload/logs"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD/dropin" "$PAYLOAD/logrotate"

for profile in cpu memory io; do
    cat > "$PAYLOAD/dropin/$profile.conf" <<EOF
[Service]
StandardOutput=append:$MNT/$profile/app.log
StandardError=append:$MNT/$profile/app.log
ReadWritePaths=/var/log/atividade3/$profile $MNT/$profile
EOF
done

cat > "$PAYLOAD/logrotate/atividade3" <<EOF
$MNT/*/app.log {
    daily
    rotate 7
    maxsize 10M
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

section "T7.1 - preparar diretorios no volume"
cap T7.1-volume-dirs "$VM_SSH 'sudo install -d -o appsvc -g appsvc -m 0750 $MNT/cpu $MNT/memory $MNT/io; ls -ld $MNT $MNT/cpu $MNT/memory $MNT/io; echo; findmnt -no SOURCE,TARGET,FSTYPE $MNT'"

section "T7.2 - redirecionar a saida dos servicos para o volume"
for profile in cpu memory io; do
    cap_soft "T7.2-dropin-$profile" "cat $PAYLOAD/dropin/$profile.conf | $VM_SSH 'sudo install -d /etc/systemd/system/app-$profile.service.d; sudo tee /etc/systemd/system/app-$profile.service.d/volume-logs.conf >/dev/null; cat /etc/systemd/system/app-$profile.service.d/volume-logs.conf'"
done
cap T7.2-restart "$VM_SSH 'sudo systemctl daemon-reload; sudo systemctl restart app-cpu app-memory app-io; sleep 3; systemctl is-active app-cpu app-memory app-io; echo; systemctl show -p StandardOutput -p StandardError app-cpu app-memory app-io'"

section "T7.3 - comprovar que os logs estao no volume"
cap T7.3-log-in-volume "$VM_SSH 'sleep 2; sudo ls -l $MNT/cpu $MNT/memory $MNT/io; echo; for f in $MNT/cpu/app.log $MNT/memory/app.log $MNT/io/app.log; do printf \"%s -> montado em %s\n\" \"\$f\" \"\$(stat -c %m \$f)\"; done; echo; sudo tail -n 2 $MNT/cpu/app.log; echo; df -h $MNT'"
cap T7.3-health "$VM_SSH 'a3-smoke'"

section "T7.4 - rotacao de logs"
cap T7.4-logrotate-install "cat $PAYLOAD/logrotate/atividade3 | $VM_SSH 'sudo tee /etc/logrotate.d/atividade3 >/dev/null; sudo chmod 0644 /etc/logrotate.d/atividade3; cat /etc/logrotate.d/atividade3'"
cap T7.4-logrotate-debug "$VM_SSH 'sudo logrotate -d /etc/logrotate.d/atividade3 2>&1 | tail -15'"
cap T7.4-logrotate-force "$VM_SSH 'sudo logrotate -f -v /etc/logrotate.d/atividade3 2>&1 | tail -12; echo; sudo ls -l $MNT/cpu $MNT/memory $MNT/io'"
cap T7.4-logrotate-timer "$VM_SSH 'systemctl list-timers logrotate.timer --no-pager; echo; systemctl is-enabled logrotate.timer'"

section "Fase 7 concluida"
