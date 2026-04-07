#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
BOARD_DIR="${ROOT_DIR}/platform/boards/imx6ull_100ask_pro"
ENV_DIR="${BOARD_DIR}/env"

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

    exec docker run --rm -it \
        -v "${ROOT_DIR}:/workspace/myplatform" \
        -w /workspace/myplatform \
        myplatform/imx6ull_100ask_pro:latest \
        "${SHELL:-/bin/bash}"
fi

echo "entered board environment for imx6ull_100ask_pro"
echo "ROOT_DIR=${ROOT_DIR}"
echo "BUILD_OUTPUT_BASE=${BUILD_OUTPUT_BASE:-myplatform/build/out}"
exec "${SHELL:-/bin/bash}"
