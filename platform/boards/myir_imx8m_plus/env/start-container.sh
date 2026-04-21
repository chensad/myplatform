#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
IMAGE="${IMAGE:-myplatform/myir_imx8m_plus:ubuntu18.04}"
CONTAINER_NAME="${CONTAINER_NAME:-myir_imx8m_plus_yocto_env}"

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is not installed" >&2
    exit 1
fi

state="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
if [[ "${state}" == "running" ]]; then
    exit 0
fi

if [[ -n "${state}" ]]; then
    docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

exec docker run -d \
    --init \
    --name "${CONTAINER_NAME}" \
    -v "${ROOT_DIR}:${ROOT_DIR}" \
    -w "${ROOT_DIR}" \
    -e LANG="${LANG:-en_US.UTF-8}" \
    -e LC_ALL="${LC_ALL:-en_US.UTF-8}" \
    -e CCACHE_DIR="${ROOT_DIR}/build/ccache" \
    -e DL_DIR="${ROOT_DIR}/build/downloads" \
    -e SSTATE_DIR="${ROOT_DIR}/build/sstate-cache" \
    "${IMAGE}" \
    tail -f /dev/null
