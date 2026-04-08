#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PRODUCT_NAME="${1:-demo_console}"
MAKE_TARGET="${2:-all}"
BOARD_DIR="${ROOT_DIR}/platform/boards/imx6ull_100ask_pro"
BOARD_ENV="${BOARD_DIR}/board.env"

if [[ ! -f "${BOARD_ENV}" ]]; then
    echo "board env not found: ${BOARD_ENV}" >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "${BOARD_ENV}"
set +a

BUILDROOT_SRC="${ROOT_DIR}/${THIRD_PARTY_BUILDROOT_DIR}"
KERNEL_SRC="${ROOT_DIR}/${THIRD_PARTY_KERNEL_DIR}"
UBOOT_SRC="${ROOT_DIR}/${THIRD_PARTY_UBOOT_DIR}"
OUTPUT_DIR="${ROOT_DIR}/${BUILD_OUTPUT_BASE}/${BOARD_NAME}/${PRODUCT_NAME}/buildroot"
DL_DIR="${ROOT_DIR}/${BUILD_OUTPUT_BASE}/downloads"
CACHED_DL_DIR="${ROOT_DIR}/../.cache/100ask-buildroot-dl"
EXTERNAL_DIR="${BOARD_DIR}/buildroot/external"
DEFCONFIG_PATH="${BOARD_DIR}/buildroot/defconfig"
MERGED_DEFCONFIG="${OUTPUT_DIR}/merged_defconfig"

if [[ ! -f "${BUILDROOT_SRC}/Makefile" ]]; then
    BUILDROOT_SRC="${ROOT_DIR}/${LEGACY_BUILDROOT_DIR}"
fi

if [[ ! -f "${BUILDROOT_SRC}/Makefile" ]]; then
    echo "buildroot source not found in third_party or legacy sdk" >&2
    exit 1
fi

if [[ ! -d "${KERNEL_SRC}" ]]; then
    KERNEL_SRC="${ROOT_DIR}/${LEGACY_KERNEL_DIR}"
fi

if [[ ! -d "${UBOOT_SRC}" ]]; then
    UBOOT_SRC="${ROOT_DIR}/${LEGACY_UBOOT_DIR}"
fi

if [[ -d "${CACHED_DL_DIR}" ]]; then
    DL_DIR="${CACHED_DL_DIR}"
fi

mkdir -p "${OUTPUT_DIR}" "${DL_DIR}"

# The mapped defconfig still references board/... paths.
# Keep a stable board alias in the output tree so legacy relative
# paths continue to resolve while the external tree is being cleaned up.
ln -snf "${BOARD_DIR}/buildroot/board" "${OUTPUT_DIR}/board"
ln -snf "${BOARD_DIR}/buildroot/board/local.mk" "${OUTPUT_DIR}/local.mk"

emit_config() {
    local config_file="$1"
    local config_dir
    local line

    config_dir="$(dirname "${config_file}")"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^#include[[:space:]]+\"([^\"]+)\"$ ]]; then
            emit_config "${config_dir}/${BASH_REMATCH[1]}"
        else
            printf '%s\n' "${line}"
        fi
    done < "${config_file}"
}

emit_config "${DEFCONFIG_PATH}" > "${MERGED_DEFCONFIG}"

make -C "${BUILDROOT_SRC}" \
    O="${OUTPUT_DIR}" \
    BR2_EXTERNAL="${EXTERNAL_DIR}" \
    BR2_DEFCONFIG="${MERGED_DEFCONFIG}" \
    BR2_DL_DIR="${DL_DIR}" \
    defconfig

#
# Linux/U-Boot sources are pinned by myplatform and injected from third_party
# through *_OVERRIDE_SRCDIR. Keep board config fragments source-agnostic.
#
make -C "${BUILDROOT_SRC}" \
    O="${OUTPUT_DIR}" \
    BR2_EXTERNAL="${EXTERNAL_DIR}" \
    BR2_DL_DIR="${DL_DIR}" \
    LINUX_OVERRIDE_SRCDIR="${KERNEL_SRC}" \
    LINUX_HEADERS_OVERRIDE_SRCDIR="${KERNEL_SRC}" \
    UBOOT_OVERRIDE_SRCDIR="${UBOOT_SRC}" \
    "${MAKE_TARGET}"

echo "buildroot source: ${BUILDROOT_SRC}"
echo "linux source: ${KERNEL_SRC}"
echo "uboot source: ${UBOOT_SRC}"
echo "output dir: ${OUTPUT_DIR}"
echo "target: ${MAKE_TARGET}"
if [[ "${BUILDROOT_SRC}" == "${ROOT_DIR}/${LEGACY_BUILDROOT_DIR}" ]]; then
    echo "warning: using legacy SDK Buildroot fallback; add third_party submodules to complete migration" >&2
fi
