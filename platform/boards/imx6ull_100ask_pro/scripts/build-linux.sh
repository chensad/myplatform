#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
OUTPUT_TAG="${1:-demo_console}"

exec make -C "${ROOT_DIR}" BOARD=imx6ull_100ask_pro OUTPUT_TAG="${OUTPUT_TAG}" linux
