#!/usr/bin/env bash
# Cloud credentials for every phase that talks to OpenStack.
#
# The account comes from `session.env` (written by automation/run.py from
# environment variables on the host); nothing here is committed.
#
# The VDI ships an `openrc.sh` from 2023 that must NOT be sourced: it points at
# `cloud5.lsd.ufcg.edu.br`, which no longer resolves, and it reads the username
# and password interactively - sourcing it blocks an unattended session.
#
# Authentication details discovered in T0.6:
#   * user domain is `external`;
#   * the project is `Provisionamento` (capital P), and scoping by name fails
#     because the project lives in a domain that is neither `external` nor
#     `Default`. Scoping by project ID works, so the ID is resolved here.

# shellcheck disable=SC1090
[ -f "$HOME/.atividade3/session.env" ] && . "$HOME/.atividade3/session.env"

resolve_project_id() {
    local wanted="$1" id
    id="$(openstack project list -f value -c ID -c Name 2>/dev/null \
        | awk -v p="$wanted" 'tolower($0) ~ tolower(p) {print $1; exit}')"
    [ -n "$id" ] && printf '%s\n' "$id"
}

cloud_login() {
    export OS_AUTH_URL="${CLOUD_AUTH_URL:-https://cloud.lsd.ufcg.edu.br:5000/v3}"
    export OS_IDENTITY_API_VERSION=3
    export OS_USERNAME="${CLOUD_USER:?CLOUD_USER is not set}"
    export OS_PASSWORD="${CLOUD_PASS:?CLOUD_PASS is not set}"
    export OS_USER_DOMAIN_NAME="${CLOUD_DOMAIN:-external}"
    export OS_REGION_NAME="${CLOUD_REGION:-RegionOne}"
    export OS_INTERFACE="${OS_INTERFACE:-public}"
    unset OS_TOKEN OS_AUTH_TOKEN OS_PROJECT_NAME OS_PROJECT_DOMAIN_NAME 2>/dev/null || true

    local project_id
    project_id="$(resolve_project_id "${CLOUD_PROJECT:-Provisionamento}")"
    if [ -n "$project_id" ]; then
        export OS_PROJECT_ID="$project_id"
    else
        # Fall back to the name; useful only if the account has a single domain.
        export OS_PROJECT_NAME="${CLOUD_PROJECT:-Provisionamento}"
        export OS_PROJECT_DOMAIN_NAME="${CLOUD_PROJECT_DOMAIN:-external}"
    fi
}
