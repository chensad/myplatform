#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PRODUCT_NAME="${1:-demo_console}"
APP_NAME="${2:-app_demo}"
APP_DIR="${ROOT_DIR}/apps/public/${APP_NAME}"

if [[ ! -d "${APP_DIR}" ]]; then
    echo "app not found: ${APP_NAME}" >&2
    exit 1
fi

echo "building app ${APP_NAME} for product ${PRODUCT_NAME}"
make -C "${APP_DIR}"
