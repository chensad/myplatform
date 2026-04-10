#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
OUTPUT_TAG="${1:-demo_console}"
MAKE_TARGET="${2:-all}"

case "${MAKE_TARGET}" in
    all)
        exec make -C "${ROOT_DIR}" BOARD=imx6ull_100ask_pro OUTPUT_TAG="${OUTPUT_TAG}" buildroot
        ;;
    linux-rebuild)
        exec make -C "${ROOT_DIR}" BOARD=imx6ull_100ask_pro OUTPUT_TAG="${OUTPUT_TAG}" linux
        ;;
    uboot-rebuild)
        exec make -C "${ROOT_DIR}" BOARD=imx6ull_100ask_pro OUTPUT_TAG="${OUTPUT_TAG}" uboot
        ;;
    busybox-rebuild)
        exec make -C "${ROOT_DIR}" BOARD=imx6ull_100ask_pro OUTPUT_TAG="${OUTPUT_TAG}" busybox
        ;;
    *)
        exec make -C "${ROOT_DIR}" BOARD=imx6ull_100ask_pro OUTPUT_TAG="${OUTPUT_TAG}" buildroot
        ;;
esac
