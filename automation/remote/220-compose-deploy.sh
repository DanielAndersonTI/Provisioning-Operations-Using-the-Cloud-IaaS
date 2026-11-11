#!/usr/bin/env bash
# Fase 26 - cutover para o Docker Compose na VM da Atividade 3.
#
# Ordem deliberada:
#   1. o compose e o arquivo de ambiente são instalados fora do home;
#   2. os diretórios de log do volume passam a pertencer ao UID do container;
#   3. as três units systemd são paradas e desabilitadas (elas ocupam as portas
#      8000-8002);
#   4. os containers sobem a partir das imagens publicadas, sem build local.
#
# O arquivo de ambiente da VM guarda apenas usuário e tag: as imagens são
# públicas, então a VM não precisa de token. O token fica só na VDI.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/lib4.sh"

require_dockerhub || exit 1

section "T26.1 — compose e arquivo de ambiente na VM"
cap T26.1-compose-upload "sha256sum $BASE/docker-compose.yml; echo; cat $BASE/docker-compose.yml | $VM_SSH 'sudo install -d -m 0755 $COMPOSE_DIR; sudo tee $COMPOSE_DIR/docker-compose.yml >/dev/null; sudo chmod 0644 $COMPOSE_DIR/docker-compose.yml; sha256sum $COMPOSE_DIR/docker-compose.yml; ls -l $COMPOSE_DIR/docker-compose.yml'"

# Sem token na VM: as três imagens são públicas. O --env-file só interpola
# DOCKERHUB_USER e IMAGE_TAG no compose, porque `sudo` não repassa o ambiente
# do usuário ubuntu.
cap T26.1-env-file "printf 'DOCKERHUB_USER=%s\nIMAGE_TAG=%s\n' '$DOCKERHUB_USER' '$IMAGE_TAG' | $VM_SSH 'sudo install -d -m 0755 ${COMPOSE_ENV%/*}; sudo tee $COMPOSE_ENV >/dev/null; sudo chmod 0600 $COMPOSE_ENV; sudo ls -l $COMPOSE_ENV; echo; sudo cat $COMPOSE_ENV'"

cap T26.1-compose-config "$VM_SSH 'cd $COMPOSE_DIR && sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml config'"

section "T26.2 — cutover: systemd para Docker Compose"
cap T26.2-state-before "$VM_SSH 'systemctl is-enabled app-cpu app-memory app-io; systemctl is-active app-cpu app-memory app-io; echo; sudo ss -ltnp | grep -E \":800[012]\" || true'"

# O pull vem ANTES de parar o systemd: se a imagem não existir no Hub ou a rede
# falhar, a fase aborta com as três aplicações ainda no ar, em vez de deixar a
# VM sem serviço nenhum.
cap T26.2-pull "$VM_SSH 'cd $COMPOSE_DIR && sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml pull'"

cap T26.2-stop-units "$VM_SSH 'sudo systemctl stop app-cpu app-memory app-io; sudo systemctl disable app-cpu app-memory app-io 2>&1 | tail -3; systemctl is-active app-cpu app-memory app-io; echo; sudo ss -ltnp | grep -E \":800[012]\" || echo \"portas 8000-8002 livres\"'"

# Dono dos diretórios só depois de parar o systemd: enquanto a aplicação antiga
# roda como appsvc do sistema, um diretório de outro UID a deixaria sem escrita.
section "T26.1 — diretórios de log do container (UID 10001)"
cap T26.1-log-dirs "$VM_SSH 'sudo install -d -o 10001 -g 10001 -m 0750 $LOG_DIR/cpu $LOG_DIR/memory $LOG_DIR/io; sudo chown -R 10001:10001 $LOG_DIR/cpu $LOG_DIR/memory $LOG_DIR/io; ls -ldn $LOG_DIR $LOG_DIR/cpu $LOG_DIR/memory $LOG_DIR/io; df -h $LOG_DIR | tail -1'"

cap T26.2-up "$VM_SSH 'cd $COMPOSE_DIR && sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml up -d --no-build; echo; sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml ps'" || {
    section "T26.2 — rollback: o Compose não subiu, devolvendo ao systemd"
    cap T26.2-rollback "$VM_SSH 'sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml down; sudo systemctl enable --now app-cpu app-memory app-io; sleep 3; systemctl is-active app-cpu app-memory app-io'"
    echo "FASE ABORTADA: as aplicações voltaram ao systemd da Atividade 3." >&2
    exit 1
}

section "T26.3 — serviços, healthchecks e logs no volume"
# O healthcheck tem start_period de 5s e interval de 15s; 20s de espera deixam
# os três containers com estado definido antes da leitura.
sleep 20

cap T26.3-ps "$VM_SSH 'cd $COMPOSE_DIR && sudo docker compose --env-file $COMPOSE_ENV -f $COMPOSE_DIR/docker-compose.yml ps; echo; sudo docker ps --format \"table {{.Names}}\t{{.Status}}\t{{.Ports}}\"'"

cap T26.3-health "$VM_SSH 'for c in poi-atividade4-cpu-1 poi-atividade4-memory-1 poi-atividade4-io-1; do printf \"%-24s \" \$c; sudo docker inspect --format \"{{if .State.Health}}{{.State.Health.Status}}{{else}}sem healthcheck{{end}}\" \$c; done'"

cap T26.3-ports "$VM_SSH 'sudo ss -ltnp | grep -E \":800[012]\"'"

cap T26.3-volume-logs "$VM_SSH 'sudo ls -l $LOG_DIR/cpu $LOG_DIR/memory $LOG_DIR/io; echo; sudo tail -n 3 $LOG_DIR/cpu/app.log $LOG_DIR/memory/app.log $LOG_DIR/io/app.log'"

cap T26.3-restart-policy "$VM_SSH 'for c in poi-atividade4-cpu-1 poi-atividade4-memory-1 poi-atividade4-io-1; do printf \"%-24s \" \$c; sudo docker inspect --format \"{{.HostConfig.RestartPolicy.Name}} / log {{.HostConfig.LogConfig.Type}} {{.HostConfig.LogConfig.Config}}\" \$c; done'"

section "T26.3 — endurecimento dos containers"
cap T26.3-hardening "$VM_SSH 'for c in poi-atividade4-cpu-1 poi-atividade4-memory-1 poi-atividade4-io-1; do printf \"%-24s \" \$c; sudo docker inspect --format \"readonly={{.HostConfig.ReadonlyRootfs}} capdrop={{.HostConfig.CapDrop}} sec={{.HostConfig.SecurityOpt}} stoptimeout={{.Config.StopTimeout}}\" \$c; done'"

section "Fase 26 concluída"
