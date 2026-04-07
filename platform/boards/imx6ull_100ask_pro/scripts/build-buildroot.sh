#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

if [[ -f "${ROOT_DIR}/100ask-user-env.sh" ]]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/100ask-user-env.sh"
fi

if declare -F buildroot_100ask_defconfig >/dev/null && declare -F buildroot_100ask_build >/dev/null; then
    buildroot_100ask_defconfig
    buildroot_100ask_build
else
    echo "buildroot helper functions are not available; source 100ask-user-env.sh first" >&2
    exit 1
fi
