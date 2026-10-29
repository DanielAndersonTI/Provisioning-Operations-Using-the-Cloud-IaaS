#!/usr/bin/env bash
# Manutencao das evidencias.
#
#   1. remove nomes antigos que sobraram de uma execucao anterior;
#   2. recaptura evidencias perdidas;
#   3. remove a senha inicial da instancia da evidencia T3.2;
#   4. refaz todos os PNGs (as versoes anteriores perderam a formatacao).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

# A checagem do plugin do Octavia no T0.4 fala com a nuvem; sem login ela sai
# com erro de autenticacao e a evidencia inteira termina com exit 1.
cloud_login

KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
VIP="${VIP:-150.165.85.77}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

section "T0.4 (regeracao) - versoes instaladas"
# A primeira chamada logo apos o login ja falhou uma vez de forma transitoria
# (a nuvem devolveu erro e o `openstack loadbalancer list` saiu 1). Tres
# tentativas com pausa evitam registrar um falso negativo na evidencia.
cap T0.4-installed-versions "dpkg-query -W -f='\${Package} \${Version}\n' python3-openstackclient python3-octaviaclient python3-psutil curl jq imagemagick tmux 2>/dev/null; echo; openstack --version; for i in 1 2 3; do openstack loadbalancer list >/dev/null 2>&1 && { echo 'plugin octavia: ok'; break; }; echo \"tentativa \$i falhou\"; sleep 5; done"

section "Recaptura de evidencias"
cap_soft T5.3-unit-content "$VM_SSH 'systemctl cat app-cpu app-memory app-io'"

section "Limpeza de nomes antigos"
for old in T5.2-runtime-user T5.3-upload-apps T5.4-checksum T5.5-install-units \
           T5.6-install-smoke T5.7-enable-start T5.8-unit-content T5.9-health-local \
           T5.10-app-logs T5.3-unit-content-old; do
    rm -f "$EVID/$old.txt" "$EVID/$old.png"
done
echo "nomes antigos removidos"

section "Redacao da senha inicial da instancia"
if [ -f "$EVID/T3.2-server-create.txt" ]; then
    sed -i -E 's/(\| adminPass[[:space:]]*\| )[^|]+/\1(omitido)/' "$EVID/T3.2-server-create.txt"
    echo "T3.2-server-create.txt: adminPass substituido por (omitido)"
fi

section "Re-renderizacao dos PNGs"
rm -f "$EVID"/*.png
made=0
failed=0
for txt in "$EVID"/*.txt; do
    [ -e "$txt" ] || continue
    png="${txt%.txt}.png"
    if render_png "$txt" "$png"; then
        made=$((made + 1))
    else
        echo "FALHOU: $(basename "$txt")"
        failed=$((failed + 1))
    fi
done
echo "PNGs gerados: $made; falhas: $failed"

section "Inventario"
printf '%-34s %-9s %s\n' ARQUIVO PNG DIMENSOES
for txt in "$EVID"/*.txt; do
    [ -e "$txt" ] || continue
    png="${txt%.txt}.png"
    size="$(identify -format '%wx%h' "$png" 2>/dev/null)"
    printf '%-34s %-9s %s\n' "$(basename "$txt" .txt)" "$([ -s "$png" ] && echo ok || echo FALTA)" "${size:-}"
done

section "Manutencao concluida"
