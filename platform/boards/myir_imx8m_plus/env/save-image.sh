#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
IMAGE="${IMAGE:-myplatform/myir_imx8m_plus:ubuntu18.04}"
OUTPUT="${1:-${ROOT_DIR}/build/myir_imx8m_plus-yocto-env_ubuntu18.04.tar}"

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is not installed" >&2
    exit 1
fi

mkdir -p "$(dirname "${OUTPUT}")"

exec docker save -o "${OUTPUT}" "${IMAGE}"
