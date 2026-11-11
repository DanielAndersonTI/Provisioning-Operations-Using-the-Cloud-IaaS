#!/usr/bin/env bash
# Fase 25 - build das três imagens na VDI e publicação no Docker Hub.
#
# O contexto de build é a raiz do repositório na VDI ($BASE): é de lá que saem
# apps/server.py, apps/<perfil>/server.py e o apps/Dockerfile. O .dockerignore
# deixa de fora evidências, resultados, automação e documentação, então a
# imagem carrega apenas o código das aplicações.
#
# O login usa o token do docker.env do operador, lido pelo run.py e entregue no
# session.env. O token nunca aparece em argumento de comando nem na evidência:
# chega ao `docker login` por --password-stdin, dentro do push-images.sh.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/lib4.sh"

require_dockerhub || exit 1

mkdir -p "$PAYLOAD"

cat > "$PAYLOAD/image-report.sh" <<'REPORT'
#!/usr/bin/env bash
# Relatório das imagens locais: id, tamanho e digest do repositório.
set -uo pipefail
user="${DOCKERHUB_USER:?DOCKERHUB_USER ausente}"
tag="${IMAGE_TAG:-1.0.0}"
printf '%-10s %-10s %-14s %-10s %s\n' PERFIL TAG ID TAMANHO DIGEST
for p in cpu memory io; do
    ref="$user/poi-$p:$tag"
    if ! docker image inspect "$ref" >/dev/null 2>&1; then
        printf '%-10s %-10s %s\n' "$p" "$tag" "imagem ausente"
        continue
    fi
    id="$(docker image inspect --format '{{.Id}}' "$ref")"
    size="$(docker image inspect --format '{{.Size}}' "$ref")"
    digest="$(docker image inspect --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{else}}-{{end}}' "$ref")"
    printf '%-10s %-10s %-14s %-10s %s\n' \
        "poi-$p" "$tag" "${id:7:12}" "$(numfmt --to=iec "$size" 2>/dev/null || echo "$size")" "$digest"
done
REPORT
chmod 0755 "$PAYLOAD/image-report.sh"

cat > "$PAYLOAD/push-images.sh" <<'PUSH'
#!/usr/bin/env bash
# Login, tag latest e push das três imagens. O token entra por stdin.
set -euo pipefail
: "${DOCKERHUB_USER:?DOCKERHUB_USER ausente}"
: "${DOCKERHUB_TOKEN:?DOCKERHUB_TOKEN ausente}"
tag="${IMAGE_TAG:-1.0.0}"

# Sair sempre deslogado: o docker login grava o token em texto puro no
# ~/.docker/config.json da VDI, e uma falha no push não pode deixar isso lá.
trap 'docker logout >/dev/null 2>&1 || true' EXIT

printf '%s' "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
for p in cpu memory io; do
    docker tag "$DOCKERHUB_USER/poi-$p:$tag" "$DOCKERHUB_USER/poi-$p:latest"
    echo "== push poi-$p:$tag"
    docker push --quiet "$DOCKERHUB_USER/poi-$p:$tag"
    echo "== push poi-$p:latest"
    docker push --quiet "$DOCKERHUB_USER/poi-$p:latest"
done
PUSH
chmod 0755 "$PAYLOAD/push-images.sh"

cat > "$PAYLOAD/hub-check.py" <<'HUB'
"""Confere as tags publicadas consultando a API pública do Docker Hub.

Sai com 1 se alguma imagem não tiver as tags esperadas: a fase 25 só termina
com sucesso quando o Hub confirma o que o push diz ter enviado.
"""
import json
import sys
import urllib.request

user = sys.argv[1]
tag = sys.argv[2] if len(sys.argv) > 2 else "1.0.0"
expected = {tag, "latest"}
missing = 0
for profile in ("cpu", "memory", "io"):
    url = f"https://hub.docker.com/v2/repositories/{user}/poi-{profile}/tags?page_size=20"
    print(f"== poi-{profile}")
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            data = json.load(response)
    except Exception as exc:  # noqa: BLE001 - qualquer falha vira evidência
        print(f"   falha ao consultar: {exc}")
        missing += 1
        continue
    if "results" not in data:
        print(f"   resposta inesperada: {data}")
        missing += 1
        continue
    found = {t.get("name", "") for t in data["results"]}
    for t in data["results"]:
        print("   %-8s %12d bytes  %s" % (
            t.get("name", "?"), t.get("full_size", 0), t.get("last_updated", "")))
    absent = expected - found
    if absent:
        print(f"   FALTANDO: {', '.join(sorted(absent))}")
        missing += 1
sys.exit(1 if missing else 0)
HUB
chmod 0644 "$PAYLOAD/hub-check.py"

section "T25.1 — contexto de build"
cap T25.1-context "cd $BASE && ls -l apps/Dockerfile .dockerignore docker-compose.yml; echo; find apps -maxdepth 2 -name '*.py' | sort; echo; echo '--- Dockerfile'; cat apps/Dockerfile"

section "T25.2 — build das três imagens"
for profile in $PROFILES; do
    cap "T25.2-build-$profile" "cd $BASE && sg docker -c 'docker build --build-arg PROFILE=$profile -f apps/Dockerfile -t $DOCKERHUB_USER/poi-$profile:$IMAGE_TAG .'"
done

cap T25.2-images "sg docker -c 'docker images --format \"table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}\"' | grep -E 'poi-(cpu|memory|io)'"

section "T25.3 — publicação no Docker Hub"
# Push sem `|| exit` mascarava a falha: o resto da fase seguia e terminava 0.
# Agora uma recusa do Hub encerra a fase com erro.
cap T25.3-push "sg docker -c \"bash $PAYLOAD/push-images.sh\"" || {
    echo "PUSH FALHOU: verifique a permissão Read & Write do token no Docker Hub." >&2
    exit 1
}

cap T25.3-report "sg docker -c \"bash $PAYLOAD/image-report.sh\" | tee $RESULTS/docker-images-$IMAGE_TAG.txt"

cap T25.3-hub "python3 $PAYLOAD/hub-check.py $DOCKERHUB_USER $IMAGE_TAG" || {
    echo "HUB NÃO CONFIRMOU AS TAGS: a publicação está incompleta." >&2
    exit 1
}

section "Fase 25 concluída"
