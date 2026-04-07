#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
usage:
  ./tools/build.sh <board> <product> [component]

examples:
  ./tools/build.sh imx6ull_100ask_pro demo_console all
  ./tools/build.sh imx6ull_100ask_pro demo_console app:app_demo
  ./tools/build.sh imx6ull_100ask_pro demo_console linux
  ./tools/build.sh imx6ull_100ask_pro demo_console buildroot
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
        "${BOARD_DIR}/scripts/build-apps.sh" app_demo
        "${BOARD_DIR}/scripts/build-linux.sh"
        "${BOARD_DIR}/scripts/build-buildroot.sh"
        ;;
    linux)
        "${BOARD_DIR}/scripts/build-linux.sh"
        ;;
    uboot)
        "${BOARD_DIR}/scripts/build-uboot.sh"
        ;;
    buildroot)
        "${BOARD_DIR}/scripts/build-buildroot.sh"
        ;;
    app:*)
        "${BOARD_DIR}/scripts/build-apps.sh" "${COMPONENT#app:}"
        ;;
    *)
        echo "unsupported component: ${COMPONENT}" >&2
        exit 1
        ;;
esac
