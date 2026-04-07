#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

if [[ -f "${ROOT_DIR}/100ask-user-env.sh" ]]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/100ask-user-env.sh"
else
    echo "missing ${ROOT_DIR}/100ask-user-env.sh" >&2
    exit 1
fi

exec "${SHELL:-/bin/bash}"
