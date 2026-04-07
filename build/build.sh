#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
usage:
  ./build/build.sh <board> <product> [component]

examples:
  ./build/build.sh imx6ull_100ask_pro demo_console all
  ./build/build.sh imx6ull_100ask_pro demo_console app:app_demo
  ./build/build.sh imx6ull_100ask_pro demo_console linux
  ./build/build.sh imx6ull_100ask_pro demo_console uboot
  ./build/build.sh imx6ull_100ask_pro demo_console buildroot
EOF
}

BOARD="${1:-}"
PRODUCT="${2:-}"
COMPONENT="${3:-all}"

if [[ -z "${BOARD}" || -z "${PRODUCT}" ]]; then
    usage
    exit 1
fi

BOARD_DIR="${ROOT_DIR}/platform/boards/${BOARD}"

if [[ ! -d "${BOARD_DIR}" ]]; then
    echo "unknown board: ${BOARD}" >&2
    exit 1
fi

case "${COMPONENT}" in
    all)
        "${BOARD_DIR}/scripts/build-apps.sh" "${PRODUCT}" app_demo
        "${BOARD_DIR}/scripts/build-buildroot.sh" "${PRODUCT}" all
        ;;
    linux)
        "${BOARD_DIR}/scripts/build-linux.sh" "${PRODUCT}"
        ;;
    uboot)
        "${BOARD_DIR}/scripts/build-uboot.sh" "${PRODUCT}"
        ;;
    buildroot)
        "${BOARD_DIR}/scripts/build-buildroot.sh" "${PRODUCT}" all
        ;;
    app:*)
        "${BOARD_DIR}/scripts/build-apps.sh" "${PRODUCT}" "${COMPONENT#app:}"
        ;;
    *)
        echo "unsupported component: ${COMPONENT}" >&2
        exit 1
        ;;
esac
