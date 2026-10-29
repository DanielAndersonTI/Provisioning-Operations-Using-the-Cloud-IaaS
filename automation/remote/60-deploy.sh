#!/usr/bin/env bash
# Fase 5 - deploy das tres aplicacoes na VM.
#
# A VM nao tem IP publico: o unico caminho do VDI ate ela e o listener SSH do
# balanceador (VIP:2222). Todo o deploy, portanto, viaja por esse canal.
#
# Estado final desta fase:
#   /opt/atividade3/apps/{server.py,cpu,memory,io}   codigo das aplicacoes
#   /etc/systemd/system/app-{cpu,memory,io}.service servicos systemd
#   /usr/local/bin/a3-smoke                          verificação rapida
#   /var/log/atividade3/<perfil>/app.log             saida das aplicacoes

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
VIP="${VIP:-150.165.85.77}"
SSH_PORT="${SSH_PORT:-2222}"
SRC="$HOME/atividade3/apps"
PAYLOAD="$HOME/atividade3/payload"

SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

vssh() { ssh $SSH_OPTS ubuntu@$VIP "$@"; }

section "T5.0 - esperar a VM responder"
ready=1
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if vssh 'true' 2>/dev/null; then ready=0; break; fi
    echo "tentativa $attempt: SSH ainda indisponivel; aguardando 10s"
    sleep 10
done
[ "$ready" -eq 0 ] || { echo "VM inacessivel pela VIP"; exit 1; }

section "T5.1 - estado base da VM"
cap T5.1-vm-baseline "$VM_SSH 'cloud-init status 2>/dev/null | head -3; echo; hostnamectl 2>/dev/null | head -3; echo; python3 -V 2>&1; echo; nproc; free -m | head -2; echo; df -h / | tail -1'"

section "T5.1 - usuario de servico e diretorios"
cap T5.1-runtime-user "$VM_SSH 'sudo useradd --system --no-create-home --shell /usr/sbin/nologin appsvc 2>/dev/null || true; sudo install -d -o root -g root -m 0755 /opt/atividade3 /opt/atividade3/apps; sudo install -d -o appsvc -g appsvc -m 0750 /var/log/atividade3 /var/log/atividade3/cpu /var/log/atividade3/memory /var/log/atividade3/io; getent passwd appsvc; ls -ld /opt/atividade3 /var/log/atividade3 /var/log/atividade3/cpu /var/log/atividade3/io'"

section "T5.2 - envio do codigo das aplicacoes"
cap T5.2-upload-apps "tar czf - -C $HOME/atividade3 apps | $VM_SSH 'sudo tar xzf - -C /opt/atividade3; find /opt/atividade3/apps -type f | sort; du -sh /opt/atividade3/apps'"

section "T5.2 - conferencia de integridade (sha256 origem x destino)"
cap T5.2-checksum "sha256sum $SRC/server.py $SRC/cpu/server.py $SRC/memory/server.py $SRC/io/server.py; echo; $VM_SSH 'sha256sum /opt/atividade3/apps/server.py /opt/atividade3/apps/cpu/server.py /opt/atividade3/apps/memory/server.py /opt/atividade3/apps/io/server.py'"

section "T5.3 - unidades systemd"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD/units"
for spec in cpu:8000 memory:8001 io:8002; do
    profile="${spec%%:*}"
    port="${spec##*:}"
    cat > "$PAYLOAD/units/app-$profile.service" <<EOF
[Unit]
Description=Atividade 3 - aplicacao $profile (porta $port)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=appsvc
Group=appsvc
WorkingDirectory=/opt/atividade3/apps
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 /opt/atividade3/apps/$profile/server.py --port $port
Restart=on-failure
RestartSec=2
TimeoutStopSec=5
StandardOutput=append:/var/log/atividade3/$profile/app.log
StandardError=append:/var/log/atividade3/$profile/app.log

# Endurecimento. A aplicacao precisa apenas de rede, de CPU e do proprio /tmp
# privado; nada em /opt e reescrito em tempo de execucao.
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=yes
ProtectSystem=full
ReadWritePaths=/var/log/atividade3/$profile

[Install]
WantedBy=multi-user.target
EOF
done

cat > "$PAYLOAD/a3-smoke" <<'EOF'
#!/usr/bin/env bash
# Verificacao rapida das tres aplicacoes.
#
# Uso:
#   a3-smoke                 checa 127.0.0.1 nas portas internas
#   A3_HOST=150.165.85.77 A3_BASE=8100 a3-smoke   checa pela VIP
#
# Sai com 0 apenas se todos os perfis responderem 200 em /health e /work.

set -uo pipefail
HOST="${A3_HOST:-127.0.0.1}"

port_of() {
    case "$1" in
        cpu)    echo "${A3_CPU_PORT:-8000}" ;;
        memory) echo "${A3_MEMORY_PORT:-8001}" ;;
        io)     echo "${A3_IO_PORT:-8002}" ;;
    esac
}

size_of() {
    case "$1" in
        cpu)    echo 10 ;;
        memory) echo 32 ;;
        io)     echo 1024 ;;
    esac
}

rc=0
printf '%-8s %-6s %-7s %-7s %9s %9s  %s\n' PERFIL PORTA HEALTH WORK TEMPO_S TAMANHO RESPOSTA
for profile in cpu memory io; do
    port="$(port_of "$profile")"
    health="$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "http://$HOST:$port/health" 2>/dev/null || echo 000)"
    size="$(size_of "$profile")"
    response="$(curl -sS -m 60 -w '\n%{http_code} %{time_total}' "http://$HOST:$port/work?size=$size" 2>/dev/null || printf '\n000 -')"
    code="$(printf '%s' "$response" | tail -1 | awk '{print $1}')"
    time_s="$(printf '%s' "$response" | tail -1 | awk '{print $2}')"
    body="$(printf '%s' "$response" | head -1 | cut -c1-90)"
    [ "$health" = "200" ] && [ "$code" = "200" ] || rc=1
    printf '%-8s %-6s %-7s %-7s %9s %9s  %s\n' "$profile" "$port" "$health" "$code" "${time_s:--}" "$size" "$body"
done
exit "$rc"
EOF

cap T5.3-install-units "tar czf - -C $PAYLOAD/units . | $VM_SSH 'sudo tar xzf - -C /etc/systemd/system; sudo chmod 0644 /etc/systemd/system/app-cpu.service /etc/systemd/system/app-memory.service /etc/systemd/system/app-io.service; ls -l /etc/systemd/system/app-*.service'"

cap T5.3-install-smoke "cat $PAYLOAD/a3-smoke | $VM_SSH 'sudo tee /usr/local/bin/a3-smoke >/dev/null; sudo chmod 0755 /usr/local/bin/a3-smoke; sudo cat /usr/local/bin/a3-smoke'"

section "T5.4 - habilitar e iniciar os servicos"
cap T5.4-enable-start "$VM_SSH 'sudo systemctl daemon-reload; sudo systemctl enable --now app-cpu app-memory app-io; sleep 3; systemctl is-enabled app-cpu app-memory app-io; systemctl is-active app-cpu app-memory app-io'"

cap T5.3-unit-content "$VM_SSH 'systemctl cat app-cpu app-memory app-io'"

section "T5.5 - teste local nas portas internas"
cap T5.5-health-local "$VM_SSH 'sudo ss -ltnp | grep -E \":800[012]\" ; echo; a3-smoke'"

section "T5.6 - log das aplicacoes"
cap T5.6-app-logs "$VM_SSH 'sudo ls -l /var/log/atividade3/*/; echo; sudo tail -n 5 /var/log/atividade3/cpu/app.log /var/log/atividade3/memory/app.log /var/log/atividade3/io/app.log'"

section "Fase 5 concluida"
