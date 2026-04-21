#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
IMAGE="${IMAGE:-myplatform/myir_imx8m_plus:ubuntu18.04}"
DOCKERFILE="${ROOT_DIR}/platform/boards/myir_imx8m_plus/env/Dockerfile"

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is not installed" >&2
    exit 1
fi

exec docker build \
    --build-arg UID="$(id -u)" \
    --build-arg GID="$(id -g)" \
    -t "${IMAGE}" \
    -f "${DOCKERFILE}" \
    "${ROOT_DIR}"
