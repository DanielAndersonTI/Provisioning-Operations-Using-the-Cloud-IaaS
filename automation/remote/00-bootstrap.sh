#!/usr/bin/env bash
# Fase 0 - preparar a VDI de acesso.
#
# Confere a maquina, a conectividade com a nuvem, localiza o arquivo RC do
# professor e instala as ferramentas usadas nas fases seguintes.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

section "T0.1 - identidade da maquina de acesso"
cap T0.1-host-info "hostnamectl; echo; uname -a; echo; whoami; id; echo; nproc; free -m | head -2; echo; df -h / | tail -1"

section "T0.2 - conectividade com a nuvem do LSD"
cap T0.2-connectivity "getent hosts cloud.lsd.ufcg.edu.br; echo; \
curl -sS -o /dev/null -w 'dashboard  -> HTTP %{http_code} em %{time_total}s\n' -m 20 https://cloud.lsd.ufcg.edu.br/ ; \
curl -sS -o /dev/null -w 'keystone   -> HTTP %{http_code} em %{time_total}s\n' -m 20 https://cloud.lsd.ufcg.edu.br:5000/v3 ; \
curl -sS -o /dev/null -w 'octavia    -> HTTP %{http_code} em %{time_total}s\n' -m 20 https://cloud.lsd.ufcg.edu.br:9876/ ; true"

section "T0.3 - arquivo OpenStack RC disponivel na imagem"
cap T0.3-openrc-files "ls -la \$HOME/*openrc*.sh 2>/dev/null; ls -la /etc/openstack 2>/dev/null; ls -la \$HOME/.config/openstack 2>/dev/null; echo; find \$HOME -maxdepth 2 -name '*openrc*' -o -maxdepth 2 -name 'clouds.yaml' 2>/dev/null | head -20; true"

section "T0.4 - instalacao das ferramentas"
cap T0.4-install-tools "export DEBIAN_FRONTEND=noninteractive; \
sudo_run apt-get -o DPkg::Lock::Timeout=180 update -qq && \
sudo_run apt-get -o DPkg::Lock::Timeout=180 install -y -qq jq curl tmux imagemagick fonts-dejavu-core python3-pip python3-psutil python3-openstackclient 2>&1 | tail -10"

section "T0.5 - cliente OpenStack"
cap T0.5-openstack-version "openstack --version 2>&1; echo; python3 -c 'import psutil; print(\"psutil\", psutil.__version__)' 2>&1"

section "T0.6 - autenticacao na nuvem"
cloud_login
echo "auth_url=$OS_AUTH_URL  user=$OS_USERNAME  project=${OS_PROJECT_ID:-$OS_PROJECT_NAME}  region=$OS_REGION_NAME  domain=$OS_USER_DOMAIN_NAME"
cap_soft T0.6-token-issue "openstack token issue -f value -c project_id -c expires 2>&1"
cap_soft T0.6-project-show "openstack project show \${OS_PROJECT_ID:-\$OS_PROJECT_NAME} 2>&1"

section "Fase 0 concluida"
