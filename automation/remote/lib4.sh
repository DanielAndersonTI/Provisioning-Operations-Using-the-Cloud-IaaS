#!/usr/bin/env bash
# Helpers específicos da Atividade 4, comuns às fases 24 a 28. Sourced, nunca
# executado sozinho: pressupõe que `lib.sh` já foi carregado (cap, cap_soft,
# section, EVID, RESULTS, BASE, sudo_run).
#
# A Atividade 4 roda sobre a infraestrutura da Atividade 3. O caminho até a VM
# continua sendo o listener SSH do balanceador (VIP:2222); o que muda é o que
# roda dentro da VM: três containers do Docker Compose no lugar das três units
# systemd.
#
# Nenhuma credencial é impressa aqui. O token do Docker Hub chega pelo
# session.env (0600, escrito pelo run.py a partir do docker.env do operador) e é
# usado sempre por `--password-stdin`, nunca como argumento de linha de comando.

KEY_PATH="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
VIP="${VIP:-150.165.85.77}"
VM_IP="${VM_IP:-10.5.9.15}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY_PATH -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

IMAGE_TAG="${IMAGE_TAG:-1.0.0}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/atividade4}"
COMPOSE_ENV="${COMPOSE_ENV:-/etc/poi-atividade4/docker.env}"
LOG_DIR="${LOG_DIR:-/mnt/atividade3-logs}"
PAYLOAD="$BASE/payload4"
PROFILES="cpu memory io"

# O usuário que executa a fase entra no grupo docker durante a instalação.
# `sg` aplica o grupo na hora, sem exigir logout/login no meio da automação.
dk() {
    sg docker -c "$*"
}
export -f dk

# Falha cedo quando o operador esqueceu de preencher o docker.env: as fases 25 e
# seguintes não têm como publicar sem usuário do Docker Hub.
require_dockerhub() {
    if [ -z "${DOCKERHUB_USER:-}" ]; then
        echo "DOCKERHUB_USER ausente: crie docker.env a partir de docker.env.example" >&2
        return 1
    fi
    if ! getent group docker >/dev/null 2>&1; then
        echo "grupo docker inexistente: execute a fase 24 primeiro" >&2
        return 1
    fi
    if ! getent group docker | cut -d: -f4 | tr ',' '\n' | grep -qx "$(id -un)"; then
        echo "usuário $(id -un) fora do grupo docker: execute a fase 24 primeiro" >&2
        return 1
    fi
}

# Caminho único para falar com o Compose na VM: arquivo de projeto fixo e
# arquivo de ambiente fora do repositório, lido por interpolação.
vm_compose() {
    ssh $SSH_OPTS ubuntu@"$VIP" "cd $COMPOSE_DIR && sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml $*"
}
export -f vm_compose
