#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
BOARD_DIR="${ROOT_DIR}/platform/boards/myir_imx8m_plus"
ENV_DIR="${BOARD_DIR}/env"
IMAGE="myplatform/myir_imx8m_plus:ubuntu18.04"
CONTAINER_NAME="${CONTAINER_NAME:-myir_imx8m_plus_yocto_env}"

if [[ -f "${ENV_DIR}/toolchain.env" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_DIR}/toolchain.env"
    set +a
fi

if [[ "${1:-}" == "--docker" ]]; then
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker is not installed" >&2
        exit 1
    fi

    "${ENV_DIR}/start-container.sh"

    exec docker exec -it \
        "${CONTAINER_NAME}" \
        "${SHELL:-/bin/bash}"
fi

echo "entered board environment for myir_imx8m_plus"
echo "ROOT_DIR=${ROOT_DIR}"
echo "BUILD_OUTPUT_BASE=${BUILD_OUTPUT_BASE:-build/out}"
exec "${SHELL:-/bin/bash}"
