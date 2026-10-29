#!/usr/bin/env bash
# Shared helpers for the remote phase scripts. Sourced, never executed alone.
#
# Every command that produces evidence goes through `cap`, which writes the
# command, its output and its exit status to evidencias/<id>.txt and renders the
# same text to evidencias/<id>.png. One call per task keeps the filenames
# aligned with the task list in docs/execucao/.

set -uo pipefail

SESSION_ENV="$HOME/.atividade3/session.env"
if [ -f "$SESSION_ENV" ]; then
    # shellcheck disable=SC1090
    . "$SESSION_ENV"
fi

BASE="$HOME/atividade3"
EVID="$BASE/evidencias"
RESULTS="$BASE/results"
LOGS="$BASE/logs"
mkdir -p "$EVID" "$RESULTS" "$LOGS"

SUDO_PASS="${SUDO_PASS:-}"

sudo_run() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        printf '%s\n' "$SUDO_PASS" | sudo -S -p '' "$@"
    fi
}
# `cap` runs its command in a fresh bash, so functions reach it through the
# environment rather than through the current shell's state.
export -f sudo_run
export SUDO_PASS

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Render the captured transcript to a terminal-looking PNG so the report can
# show an image per task.
#
# Two details matter here:
#   * the ImageMagick policy of this image forbids reading text from a file
#     (`caption:@file` and `label:@file` are blocked), so the text goes inline;
#   * very long lines made `caption:` fail the size limit and spend minutes in a
#     font-size search, so the text is wrapped first and rendered through pango,
#     which takes about a second per image;
#   * `%`, `&`, `<` and `>` are escaped because ImageMagick expands them.
render_png() {
    local txt="$1" png="$2"
    command -v convert >/dev/null 2>&1 || return 0

    # The font must be given as a *family name*: the pango coder resolves it
    # through fontconfig, so a file path silently falls back to the default
    # proportional face and every table in the evidence stops lining up.
    local font="DejaVu Sans Mono"
    [ -n "$(fc-match --format=%{file} "$font" 2>/dev/null)" ] || font="monospace"

    # Canvas width follows the longest line, so a wide `openstack show` table is
    # rendered whole instead of being wrapped in the middle of a row. Lines
    # beyond 300 columns are still folded: past that point the image stops being
    # readable at report size anyway.
    local maxlen foldw width
    maxlen="$(awk '{ if (length > m) m = length } END { print m + 0 }' "$txt" 2>/dev/null)"
    [ -n "$maxlen" ] && [ "$maxlen" -gt 0 ] || maxlen=80
    foldw=110
    if [ "$maxlen" -gt 110 ]; then foldw="$maxlen"; [ "$foldw" -gt 300 ] && foldw=300; fi
    width=$(( foldw * 9 + 60 ))
    [ "$width" -lt 760 ] && width=760

    local wrapped
    wrapped="$(mktemp)"
    # Line breaks survive only with pango markup disabled: as markup, a newline
    # is ordinary whitespace and the transcript collapses into one paragraph.
    # `%` stays escaped because ImageMagick still expands it as a property.
    fold -s -w "$foldw" "$txt" 2>/dev/null | sed -e 's/%/%%/g' >"$wrapped"
    if timeout 60 convert -background '#0b0f14' -fill '#d8dee9' -font "$font"         -pointsize 13 -size "${width}x" -bordercolor '#0b0f14' -border 18         -define pango:markup=false pango:"$(cat "$wrapped")" "$png" 2>/dev/null; then
        rm -f "$wrapped"
        return 0
    fi
    if timeout 60 convert -background '#0b0f14' -fill '#d8dee9'         -pointsize 13 -size "${width}x" -bordercolor '#0b0f14' -border 18         -define pango:markup=false pango:"$(cat "$wrapped")" "$png" 2>/dev/null; then
        rm -f "$wrapped"
        return 0
    fi
    rm -f "$wrapped"
    return 1
}

# cap <id> <command...>
cap() {
    local id="$1"
    shift
    local cmd="$*"
    local txt="$EVID/$id.txt"
    local png="$EVID/$id.png"
    local rc=0

    {
        printf '$ %s\n' "$cmd"
        printf '# host=%s user=%s utc=%s\n\n' "$(hostname)" "$(whoami)" "$(utc_now)"
    } >"$txt"

    bash -lc "$cmd" >>"$txt" 2>&1 || rc=$?

    printf '\n[exit %s] %s\n' "$rc" "$(utc_now)" >>"$txt"
    render_png "$txt" "$png" || true
    echo "----- $id (exit $rc) -----"
    cat "$txt"
    echo "--------------------------"
    return $rc
}

# cap_retry <id> <tentativas> <command...>
#
# O balanceador compartilhado da disciplina responde HTTP 409 "is immutable"
# enquanto outro grupo aplica uma mudanca, entao as criacoes de listener, pool e
# membro precisam de nova tentativa. A evidencia guarda a tentativa que deu certo.
cap_retry() {
    local id="$1" tries="$2"
    shift 2
    local cmd="$*"
    local tmp attempt rc=1
    tmp="$(mktemp)"
    for attempt in $(seq 1 "$tries"); do
        {
            printf '$ %s
' "$cmd"
            printf '# host=%s user=%s utc=%s (tentativa %s)

'                 "$(hostname)" "$(whoami)" "$(utc_now)" "$attempt"
            bash -lc "$cmd" 2>&1
            rc=$?
            printf '
[exit %s] %s
' "$rc" "$(utc_now)"
        } >"$tmp"
        [ "$rc" -eq 0 ] && break
        # Ha 409 que nao passam sozinhos: o recurso ja existe. Repetir so gasta
        # tempo, entao esses casos encerram a repeticao na primeira tentativa.
        if grep -qE 'already has a health monitor|Another member on this pool|already exists' "$tmp"; then
            echo "tentativa $attempt falhou com erro definitivo (recurso ja existe); sem repeticao"
            break
        fi
        echo "tentativa $attempt falhou; repetindo em 15s"
        sleep 15
    done
    mv "$tmp" "$EVID/$id.txt"
    render_png "$EVID/$id.txt" "$EVID/$id.png" || true
    echo "----- $id (exit $rc) -----"
    cat "$EVID/$id.txt"
    echo "--------------------------"
    return $rc
}

# Same as cap, but never fails the phase: used for listings that may legitimately
# return non-zero (a resource that does not exist yet, for example).
cap_soft() {
    cap "$@"
    return 0
}

section() {
    printf '\n\n========== %s ==========\n' "$*"
}

# evidence_from <id> <titulo> <corpo>
# Grava um corpo de texto como evidencia, com o mesmo preambulo de `cap`.
evidence_from() {
    local id="$1" title="$2" body="$3"
    local txt="$EVID/$id.txt"
    {
        printf '$ %s\n' "$title"
        printf '# host=%s user=%s utc=%s\n\n' "$(hostname)" "$(whoami)" "$(utc_now)"
        printf '%s\n' "$body"
        printf '\n[exit 0] %s\n' "$(utc_now)"
    } >"$txt"
    render_png "$txt" "$EVID/$id.png" || true
    echo "----- $id -----"
    printf '%s\n' "$body"
    echo "----------------"
}

# port_of <perfil> - porta externa (VIP) de cada aplicacao.
port_of() {
    case "$1" in
        cpu) echo "${A3_CPU_PORT:-8100}" ;;
        memory) echo "${A3_MEMORY_PORT:-8101}" ;;
        io) echo "${A3_IO_PORT:-8102}" ;;
    esac
}

# run_scenario <tag> <run_id> <perfil> <tamanho> <concorrencia> <duracao>
#
# Executa um cenario completo: monitor dentro da VM, iostat quando o perfil e IO,
# aquecimento descartado, janela medida, contadores do app antes e depois, e a
# evidencia com o resumo. Depende de VIP, VM_SSH, WARMUP e INTERVAL definidos
# pela fase que a chama.
run_scenario() {
    local tag="$1" run_id="$2" profile="$3" size="$4" concurrency="$5" duration="$6"
    local port url mon_seconds monitor_pid iostat_pid=""
    port="$(port_of "$profile")"
    url="http://$VIP:$port/work?size=$size"
    mon_seconds=$(( duration + WARMUP + 5 ))

    echo
    echo "=== $run_id  url=$url  concorrencia=$concurrency  janela=${duration}s ==="

    curl -s --max-time 10 "http://$VIP:$port/metrics" >"/tmp/before-$run_id.json" 2>/dev/null || echo '{}' >"/tmp/before-$run_id.json"

    $VM_SSH "python3 /opt/atividade3/scripts/monitor.py --scenario $run_id --seconds $mon_seconds --interval $INTERVAL --out /tmp/mon-$run_id.csv" \
        >"$LOGS/monitor-$run_id.log" 2>&1 &
    monitor_pid=$!

    if [ "$profile" = "io" ]; then
        $VM_SSH "iostat -dx 1 $mon_seconds > /tmp/iostat-$run_id.txt 2>&1" >/dev/null 2>&1 &
        iostat_pid=$!
    fi

    sleep 2
    python3 "$BASE/scripts/load_test.py" --url "$url" --scenario "$profile" \
        --level "$concurrency" --concurrency "$concurrency" \
        --duration "$WARMUP" --run-id "warmup-$run_id" \
        --out "$RESULTS/warmup.csv" >/dev/null 2>&1

    python3 "$BASE/scripts/load_test.py" --url "$url" --scenario "$profile" \
        --level "$concurrency" --concurrency "$concurrency" \
        --duration "$duration" --run-id "$run_id" \
        --out "$RESULTS/measurements-v2.csv" >"$LOGS/load-$run_id.json" 2>&1

    wait "$monitor_pid" 2>/dev/null || true
    [ -n "$iostat_pid" ] && { wait "$iostat_pid" 2>/dev/null || true; }

    $VM_SSH "cat /tmp/mon-$run_id.csv" >"$RESULTS/resources-v2-$run_id.csv" 2>/dev/null || true

    if [ "$profile" = "io" ]; then
        $VM_SSH "cat /tmp/iostat-$run_id.txt" >"$RESULTS/iostat-$run_id.txt" 2>/dev/null || true
        python3 "$BASE/scripts/parse_iostat.py" "$RESULTS/iostat-$run_id.txt" "$run_id" "$RESULTS/iostat.csv" \
            >"$LOGS/iostat-$run_id.log" 2>&1 \
            || echo "AVISO: parse_iostat falhou em $run_id" >&2
    fi

    curl -s --max-time 10 "http://$VIP:$port/metrics" >"/tmp/after-$run_id.json" 2>/dev/null || echo '{}' >"/tmp/after-$run_id.json"
    python3 "$BASE/scripts/app_metrics.py" "/tmp/before-$run_id.json" "/tmp/after-$run_id.json" "$run_id" "$RESULTS/app-metrics.csv" >/dev/null 2>&1 || true

    evidence_from "$tag" "curl $url + python3 scripts/load_test.py --concurrency $concurrency --duration $duration" \
        "$(python3 "$BASE/scripts/run_summary.py" "$RESULTS" "$run_id")"
}
