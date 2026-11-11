#!/usr/bin/env bash
# Fase 24 - Docker Engine e plugin Compose na VDI e na VM.
#
# A VDI é quem constrói e publica as imagens; a VM apenas baixa e executa os
# containers. As duas instalam o mesmo pacote, com a mesma ordem de tentativas:
#
#   1. pacotes da distribuição (docker.io + docker-compose-v2), que já estão no
#      espelho apt usado pelo laboratório;
#   2. repositório oficial da Docker (docker-ce + docker-compose-plugin), quando
#      o pacote da distribuição não traz o plugin do Compose v2;
#   3. binário standalone do Compose em /usr/local/lib/docker/cli-plugins, como
#      último recurso.
#
# A evidência registra qual caminho funcionou, porque isso muda o que o
# relatório pode afirmar sobre a instalação.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/lib4.sh"

mkdir -p "$PAYLOAD"
cat > "$PAYLOAD/install-docker.sh" <<'INSTALL'
#!/usr/bin/env bash
# Instala Docker Engine e o plugin Compose. Executado como root na VDI (via
# sudo_run) e na VM (via `sudo bash -s`). Idempotente: repetir não reinstala.
set -uo pipefail

log() { printf '== %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
compose_ok() { docker compose version >/dev/null 2>&1; }

# Aplicar o grupo docker ao usuário que administra a máquina. Precisa acontecer
# também quando a instalação é pulada: a VDI pode já ter Docker de uma execução
# anterior e o usuário continuar fora do grupo, e aí `sg docker` pediria senha e
# travaria a fase (o run.py não encaminha stdin).
apply_docker_group() {
    [ "$(id -u)" -eq 0 ] || return 0
    getent group docker >/dev/null 2>&1 || return 0
    for u in ${SUDO_USER:-} ubuntu; do
        if [ -n "$u" ] && id "$u" >/dev/null 2>&1; then
            usermod -aG docker "$u" && log "usuário $u adicionado ao grupo docker"
        fi
    done
}

if have docker && compose_ok; then
    log "docker e plugin Compose já instalados"
    systemctl enable --now docker || log "systemctl enable --now docker falhou"
    apply_docker_group
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# 1) pacotes da distribuição
if ! have docker; then
    log "tentativa 1: docker.io da distribuição"
    apt-get -o DPkg::Lock::Timeout=180 update -qq || log "apt-get update falhou"
    apt-get -o DPkg::Lock::Timeout=180 install -y -qq docker.io || log "docker.io indisponível"
fi
if ! compose_ok; then
    log "tentativa 1: docker-compose-v2 da distribuição"
    apt-get -o DPkg::Lock::Timeout=180 install -y -qq docker-compose-v2 \
        || apt-get -o DPkg::Lock::Timeout=180 install -y -qq docker-compose-plugin \
        || log "nenhum pacote de Compose v2 na distribuição"
fi

# 2) repositório oficial da Docker
if ! compose_ok; then
    log "tentativa 2: repositório oficial da Docker"
    apt-get -o DPkg::Lock::Timeout=180 install -y -qq ca-certificates curl gnupg || true
    install -m 0755 -d /etc/apt/keyrings
    if curl -fsSL --max-time 60 https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc; then
        chmod a+r /etc/apt/keyrings/docker.asc
        # shellcheck disable=SC1091
        . /etc/os-release
        printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
            "$(dpkg --print-architecture)" "${VERSION_CODENAME:-jammy}" \
            > /etc/apt/sources.list.d/docker.list
        apt-get -o DPkg::Lock::Timeout=180 update -qq || true
        apt-get -o DPkg::Lock::Timeout=180 install -y -qq \
            docker-ce docker-ce-cli containerd.io docker-compose-plugin \
            || log "pacotes do repositório oficial indisponíveis"
    else
        log "chave do repositório oficial inacessível"
    fi
fi

# 3) binário standalone do Compose
if ! compose_ok; then
    log "tentativa 3: binário standalone do Compose"
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) arch=x86_64 ;;
        aarch64|arm64) arch=aarch64 ;;
    esac
    install -d /usr/local/lib/docker/cli-plugins
    curl -fsSL --max-time 120 \
        "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-$arch" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose \
        && chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose \
        || log "download do binário do Compose falhou"
fi

systemctl enable --now docker || log "systemctl enable --now docker falhou"
apply_docker_group

if ! have docker || ! docker info >/dev/null 2>&1; then
    log "ERRO: o daemon do Docker não respondeu"
    exit 1
fi
if ! compose_ok; then
    log "ERRO: o plugin Compose não está disponível"
    exit 1
fi
log "Docker e Compose prontos"
INSTALL
chmod 0755 "$PAYLOAD/install-docker.sh"

section "T24.1 — Docker Engine e Compose na VDI"
cap T24.1-vdi-install "sudo_run bash $PAYLOAD/install-docker.sh"

# Cinto e suspensório: o install já aplica o grupo, mas `sg` bloqueia pedindo
# senha se o usuário ficar de fora, e o run.py não encaminha stdin para
# responder. Esta chamada garante o grupo antes de qualquer `sg docker`.
cap T24.1-vdi-group "sudo_run usermod -aG docker $(id -un); getent group docker; sudo_run docker info --format 'servidor {{.ServerVersion}}'"

cap T24.1-vdi-versions "sg docker -c 'docker version --format \"cliente {{.Client.Version}} / servidor {{.Server.Version}}\"'; sg docker -c 'docker compose version'; sg docker -c 'docker info --format \"driver={{.Driver}} root={{.DockerRootDir}}\"'; echo; df -h /var/lib/docker | tail -1"

cap T24.1-vdi-permissions "id; getent group docker; sg docker -c 'docker ps'"

section "T24.2 — Docker Engine e Compose na VM"
cap T24.2-vm-install "cat $PAYLOAD/install-docker.sh | $VM_SSH 'sudo bash -s'"

cap T24.2-vm-versions "$VM_SSH 'sudo docker version --format \"cliente {{.Client.Version}} / servidor {{.Server.Version}}\"; sudo docker compose version; sudo docker info --format \"driver={{.Driver}} root={{.DockerRootDir}}\"; echo; df -h /var/lib/docker | tail -1'"

section "T24.2 — volume da Atividade 3 ainda anexado"
cap T24.2-vm-volume "$VM_SSH 'df -h $LOG_DIR | tail -1; mount | grep atividade3-logs || true; ls -la $LOG_DIR; systemctl is-active app-cpu app-memory app-io'"

section "Fase 24 concluída"
