#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
usage:
  ./build/build.sh <board> [component]
  ./build/build.sh <board> <output_tag> [component]

examples:
  ./build/build.sh imx6ull_100ask_pro
  ./build/build.sh imx6ull_100ask_pro buildroot
  ./build/build.sh imx6ull_100ask_pro demo_console buildroot
  ./build/build.sh imx6ull_100ask_pro app:app_demo
EOF
}

BOARD="${1:-}"
ARG2="${2:-}"
ARG3="${3:-}"
OUTPUT_TAG=""
COMPONENT="all"

if [[ -z "${BOARD}" ]]; then
    usage
    exit 1
fi

if [[ -n "${ARG3}" ]]; then
    OUTPUT_TAG="${ARG2}"
    COMPONENT="${ARG3}"
elif [[ -n "${ARG2}" ]]; then
    case "${ARG2}" in
        all|buildroot|linux|uboot|vars|help|app:*)
            COMPONENT="${ARG2}"
            ;;
        *)
            OUTPUT_TAG="${ARG2}"
            ;;
    esac
fi

MAKE_ARGS=(
    -C "${ROOT_DIR}"
    "BOARD=${BOARD}"
)

if [[ -n "${OUTPUT_TAG}" ]]; then
    MAKE_ARGS+=("OUTPUT_TAG=${OUTPUT_TAG}")
fi

case "${COMPONENT}" in
    all|buildroot|linux|uboot|vars|help)
        exec make "${MAKE_ARGS[@]}" "${COMPONENT}"
        ;;
    app:*)
        exec make "${MAKE_ARGS[@]}" "APP=${COMPONENT#app:}" app
        ;;
    *)
        echo "unsupported component: ${COMPONENT}" >&2
        exit 1
        ;;
esac
