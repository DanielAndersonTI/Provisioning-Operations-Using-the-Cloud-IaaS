#!/usr/bin/env bash
# Fase 17 - matriz de vagas: o limite vem do flavor ou do numero de vagas?
#
# Os cenarios pela VIP mostram a vazao parando de crescer por volta de 20 a 33
# requisicoes por segundo sem encher as vagas do servidor: o caminho VDI ->
# balanceador -> VM limita a chegada antes da aplicacao. Para observar a decisao
# de admissao do proprio servidor, esta fase sobe uma copia manual da aplicacao
# numa porta fora do balanceador (8010 CPU, 8011 IO), com `--max-concurrency`
# escolhido, e gera a carga DENTRO da VM contra 127.0.0.1.
#
# Cada celula e repetida tres vezes, porque a variancia da carga local e o que
# separa uma diferenca real entre numeros de vagas de ruido de agendamento.
#
# Ressalva declarada no relatorio: cliente e servidor dividem os mesmos dois
# vCPUs, entao os valores absolutos nao se comparam com os da VIP. O que se le
# aqui e a forma: como vazao, recusas e espera mudam quando se muda o numero de
# vagas com a mesma carga.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"

VIP="${VIP:-150.165.85.77}"
KEY="$HOME/.ssh/${KEY_NAME:-atividade3-daniel-ranya}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"
VM_SSH="ssh $SSH_OPTS ubuntu@$VIP"

MNT="${MNT:-/mnt/atividade3-logs}"
DURATION="${DURATION:-20}"
REPS="${REPS:-3}"
CPU_SLOTS="${CPU_SLOTS:-1 4 32}"
IO_SLOTS="${IO_SLOTS:-4 8 16}"
CPU_CLIENTS="${CPU_CLIENTS:-8}"
IO_CLIENTS="${IO_CLIENTS:-16}"

port_of_vagas() {
    case "$1" in
        cpu) echo 8010 ;;
        io) echo 8011 ;;
    esac
}

size_of() {
    case "$1" in
        cpu) echo 10 ;;
        io) echo 1024 ;;
    esac
}

# A copia manual roda com o mesmo usuario dos servicos (appsvc) e, no perfil IO,
# no mesmo diretorio de trabalho no volume: assim a unica coisa que muda entre
# as celulas e o numero de vagas.
start_vagas_server() {
    local profile="$1" port="$2" slots="$3" run_id="$4" work_dir=""
    [ "$profile" = "io" ] && work_dir="A3_WORK_DIR=$MNT/io"
    $VM_SSH "sudo -u appsvc env PYTHONUNBUFFERED=1 $work_dir bash -c 'echo \$\$ > /tmp/vagas.pid; exec python3 /opt/atividade3/apps/$profile/server.py --port $port --max-concurrency $slots > /tmp/vagas-$run_id.log 2>&1 < /dev/null' >/dev/null 2>&1 & sleep 2; cat /tmp/vagas-$run_id.log" 2>&1
}

stop_vagas_server() {
    local port="$1"
    $VM_SSH "sudo kill \$(cat /tmp/vagas.pid 2>/dev/null) 2>/dev/null; sleep 1; sudo pkill -u appsvc -f 'port $port' 2>/dev/null; rm -f /tmp/vagas.pid; echo parado" >/dev/null 2>&1 || true
}

section "T15.1 - copia manual da aplicacao e estado dos servicos"
body="$($VM_SSH "systemctl is-active app-cpu app-memory app-io; echo; sudo ss -ltnp 2>/dev/null | grep -E ':(8000|8001|8002|8010|8011)\b' || true; echo; nproc; free -m | head -2" 2>&1)"
evidence_from T15.1-manual-server \
    "ssh ... 'systemctl is-active app-cpu app-memory app-io; ss -ltnp | grep :800[0-2]'" "$body"

rm -f "$RESULTS/measurements-vagas.csv" "$RESULTS/app-metrics-vagas.csv"
$VM_SSH 'rm -f /tmp/vagas.csv' >/dev/null 2>&1 || true

for profile in cpu io; do
    port="$(port_of_vagas "$profile")"
    size="$(size_of "$profile")"
    if [ "$profile" = "cpu" ]; then
        slots_list="$CPU_SLOTS"; clients="$CPU_CLIENTS"
    else
        slots_list="$IO_SLOTS"; clients="$IO_CLIENTS"
    fi

    for slots in $slots_list; do
        for rep in $(seq 1 "$REPS"); do
            run_id="vagas-$profile-w$slots-c$clients-r$rep"
            url="http://127.0.0.1:$port/work?size=$size"

            section "$run_id - $slots vagas, $clients clientes"

            stop_vagas_server "$port"
            start_line="$(start_vagas_server "$profile" "$port" "$slots" "$run_id")"

            # So mede depois da aplicacao responder: a subida do processo nao
            # entra na janela.
            $VM_SSH "for i in \$(seq 1 30); do curl -sf --max-time 2 http://127.0.0.1:$port/health >/dev/null && break; sleep 0.5; done; curl -s --max-time 5 http://127.0.0.1:$port/metrics" >"/tmp/before-$run_id.json" 2>/dev/null || echo '{}' >"/tmp/before-$run_id.json"

            # O monitor roda na VM: cliente e servidor dividem os mesmos vCPUs,
            # entao a leitura e do conjunto, e nao so da aplicacao.
            $VM_SSH "python3 /opt/atividade3/scripts/monitor.py --scenario $run_id --seconds $((DURATION + 5)) --interval 0.5 --out /tmp/mon-$run_id.csv" \
                >"$LOGS/monitor-$run_id.log" 2>&1 &
            monitor_pid=$!

            $VM_SSH "python3 /opt/atividade3/scripts/load_test.py --url '$url' --scenario '$profile' --level $clients --concurrency $clients --duration $DURATION --run-id $run_id --out /tmp/vagas.csv" \
                >"$LOGS/load-$run_id.json" 2>&1

            wait "$monitor_pid" 2>/dev/null || true
            $VM_SSH "cat /tmp/mon-$run_id.csv" >"$RESULTS/resources-vagas-$run_id.csv" 2>/dev/null || true

            $VM_SSH "curl -s --max-time 5 http://127.0.0.1:$port/metrics" >"/tmp/after-$run_id.json" 2>/dev/null || echo '{}' >"/tmp/after-$run_id.json"
            python3 "$BASE/scripts/app_metrics.py" "/tmp/before-$run_id.json" "/tmp/after-$run_id.json" "$run_id" "$RESULTS/app-metrics-vagas.csv" >/dev/null 2>&1 || true

            $VM_SSH 'cat /tmp/vagas.csv' >"$RESULTS/measurements-vagas.csv" 2>/dev/null || true

            stop_vagas_server "$port"

            evidence_from "T15.2-$run_id" \
                "ssh ... 'python3 /opt/atividade3/scripts/load_test.py --url $url --concurrency $clients --duration $DURATION --run-id $run_id'" \
                "$(printf 'servidor: %s\n\n%s' "$start_line" "$(python3 "$BASE/scripts/vagas_summary.py" "$RESULTS" "$run_id" "$slots")")"
        done
    done
done

section "T15.3 - servicos originais intactos"
body="$($VM_SSH "systemctl is-active app-cpu app-memory app-io; echo; for port in 8000 8001 8002; do printf '%s -> ' \$port; curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://127.0.0.1:\$port/health; done; echo; sudo ss -ltnp 2>/dev/null | grep -E ':(8000|8001|8002|8010|8011)\b' || true" 2>&1)"
evidence_from T15.3-services-intact \
    "ssh ... 'systemctl is-active app-cpu app-memory app-io; curl 127.0.0.1:800[0-2]/health'" "$body"

section "Fase 17 concluida"
