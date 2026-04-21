#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
YOCTO_DIR="${ROOT_DIR}/third_party/yocto/yocto_5.10.72"
BUILD_DIR="../../../build/out/myir_imx8m_plus/xwayland/yocto"
CONTAINER_NAME="${CONTAINER_NAME:-myir_imx8m_plus_yocto_env}"

"$(dirname "${BASH_SOURCE[0]}")/start-container.sh"

exec docker exec -it "${CONTAINER_NAME}" bash -lc "
set -eo pipefail
cd \"${YOCTO_DIR}\"
export EULA=1
export DISTRO=fsl-imx-xwayland
export MACHINE=myd-jx8mp
set +u
source \"${YOCTO_DIR}/setup-environment\" \"${BUILD_DIR}\" >/dev/null
set -u
bitbake myir-image-full
"
