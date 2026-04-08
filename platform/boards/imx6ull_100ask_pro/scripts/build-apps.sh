#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
OUTPUT_TAG="${1:-demo_console}"
APP_NAME="${2:-app_demo}"

exec make -C "${ROOT_DIR}" BOARD=imx6ull_100ask_pro OUTPUT_TAG="${OUTPUT_TAG}" APP="${APP_NAME}" app
