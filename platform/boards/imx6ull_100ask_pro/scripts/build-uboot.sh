#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PRODUCT_NAME="${1:-demo_console}"

exec "${ROOT_DIR}/platform/boards/imx6ull_100ask_pro/scripts/build-buildroot.sh" "${PRODUCT_NAME}" uboot-rebuild
