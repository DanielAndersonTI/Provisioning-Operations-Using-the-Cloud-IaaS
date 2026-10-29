#!/usr/bin/env bash
# Fase 2 - par de chaves para o acesso SSH.
#
# A chave privada nunca entra em evidencia nem no repositorio: ela fica em
# ~/.ssh dentro da VDI e so a impressao digital e registrada.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib.sh"
# shellcheck disable=SC1091
. "$HERE/cloud_login.sh"

cloud_login

KEY_NAME="${KEY_NAME:-atividade3-daniel-ranya}"
KEY="$HOME/.ssh/$KEY_NAME"

section "T2.1 - criacao do par de chaves"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$KEY" ]; then
    echo "chave $KEY_NAME ja existe localmente; reutilizando"
else
    umask 077
    openstack keypair create "$KEY_NAME" > "$KEY" 2>/dev/null
fi
chmod 600 "$KEY"
ssh-keygen -y -f "$KEY" > "$KEY.pub" 2>/dev/null

cap T2.1-keypair-list "openstack keypair list"
cap T2.1-key-fingerprint "echo 'chave privada:'; ls -l $KEY; echo; echo 'chave publica:'; ls -l $KEY.pub; echo; ssh-keygen -lf $KEY.pub"

section "Fase 2 concluida"
