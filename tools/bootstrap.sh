#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOARD="${1:-imx6ull_100ask_pro}"
BOARD_DIR="${ROOT_DIR}/platform/boards/${BOARD}"
ENV_DIR="${BOARD_DIR}/env"

if [[ ! -d "${BOARD_DIR}" ]]; then
    echo "unknown board: ${BOARD}" >&2
    exit 1
fi

required_cmds=(
    git
    make
    gcc
    g++
    rsync
    python3
    sed
    awk
)

optional_cmds=(
    docker
    ccache
)

missing=0

echo "checking required host tools for ${BOARD}"
for cmd in "${required_cmds[@]}"; do
    if command -v "${cmd}" >/dev/null 2>&1; then
        echo "  ok  ${cmd}"
    else
        echo "  miss ${cmd}" >&2
        missing=1
    fi
done

echo
echo "checking optional host tools"
for cmd in "${optional_cmds[@]}"; do
    if command -v "${cmd}" >/dev/null 2>&1; then
        echo "  ok  ${cmd}"
    else
        echo "  skip ${cmd}"
    fi
done

echo
echo "checking third_party submodules"
git -C "${ROOT_DIR}" submodule status || true

mkdir -p \
    "${ROOT_DIR}/build/out" \
    "${ROOT_DIR}/build/downloads" \
    "${ROOT_DIR}/build/ccache" \
    "${ROOT_DIR}/build/logs"

echo
echo "workspace directories prepared under ${ROOT_DIR}/build"

if [[ -f "${ENV_DIR}/toolchain.env" ]]; then
    echo
    echo "board env file: ${ENV_DIR}/toolchain.env"
fi

if [[ "${missing}" -ne 0 ]]; then
    echo
    echo "host environment is incomplete" >&2
    exit 1
fi

echo
echo "host environment looks ready"
