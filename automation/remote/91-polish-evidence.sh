#!/usr/bin/env bash
# Fase 9.0 - recaptura de evidencias com comandos corrigidos.
#
# Tres capturas das fases 5 e 7 sairam com o comando certo apontando para o
# lugar errado: o curinga era expandido pelo shell do usuario `ubuntu` antes do
# `sudo`, e `ubuntu` nao tem permissao de leitura nos diretorios 0750 do
# `appsvc`. O efeito no systemd era nenhum; o efeito na evidencia era uma
# mensagem de "Permission denied" que parece defeito. Aqui as tres sao refeitas
# resolvendo o curinga ja como root.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

VM="${VM_NAME:-vm-daniel-ranya}"
VIP="${VIP:-150.165.85.77}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

section "T5.1 - diretorios do usuario de servico"
cap T5.1-runtime-user "$VM_SSH 'getent passwd appsvc; echo; sudo ls -ld /opt/atividade3 /opt/atividade3/apps /var/log/atividade3 /var/log/atividade3/cpu /var/log/atividade3/memory /var/log/atividade3/io'"

section "T5.6 - logs da fase 5 (antes da mudanca para o volume)"
cap T5.6-app-logs "$VM_SSH 'sudo sh -c \"ls -l /var/log/atividade3/*/\"; echo; sudo tail -n 2 /var/log/atividade3/cpu/app.log /var/log/atividade3/memory/app.log /var/log/atividade3/io/app.log'"

section "T7.3 - logs no volume"
cap T7.3-log-in-volume "$VM_SSH 'sudo sh -c \"ls -l /mnt/atividade3-logs/cpu /mnt/atividade3-logs/memory /mnt/atividade3-logs/io\"; echo; for f in /mnt/atividade3-logs/cpu/app.log /mnt/atividade3-logs/memory/app.log /mnt/atividade3-logs/io/app.log; do printf \"%s -> montado em %s\\n\" \"\$f\" \"\$(sudo stat -c %m \$f)\"; done; echo; sudo tail -n 2 /mnt/atividade3-logs/cpu/app.log; echo; df -h /mnt/atividade3-logs'"

section "Polimento concluido"
