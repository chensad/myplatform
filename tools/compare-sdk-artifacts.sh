#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_DIR="${ROOT_DIR}/../100ask_imx6ull-sdk/Buildroot_2020.02.x/output"
MP_DIR="${ROOT_DIR}/build/out/imx6ull_100ask_pro/demo_console/buildroot"

usage() {
    cat <<'EOF'
usage:
  ./tools/compare-sdk-artifacts.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! -d "${SDK_DIR}" ]]; then
    echo "missing SDK output: ${SDK_DIR}" >&2
    exit 1
fi

if [[ ! -d "${MP_DIR}" ]]; then
    echo "missing myplatform output: ${MP_DIR}" >&2
    exit 1
fi

declare -a FILES=(
    "images/u-boot-dtb.imx"
    "images/zImage"
    "images/100ask_imx6ull-14x14.dtb"
    "images/rootfs.ext2"
)

echo "== File Compare =="
for rel in "${FILES[@]}"; do
    sdk="${SDK_DIR}/${rel}"
    mp="${MP_DIR}/${rel}"
    echo "-- ${rel}"
    if [[ ! -f "${sdk}" || ! -f "${mp}" ]]; then
        echo "missing file in one side"
        echo
        continue
    fi
    sdk_sha="$(sha256sum "${sdk}" | awk '{print $1}')"
    mp_sha="$(sha256sum "${mp}" | awk '{print $1}')"
    sdk_size="$(stat -c '%s' "${sdk}")"
    mp_size="$(stat -c '%s' "${mp}")"
    echo "sdk size: ${sdk_size}"
    echo "myplatform size: ${mp_size}"
    echo "sdk sha256: ${sdk_sha}"
    echo "myplatform sha256: ${mp_sha}"
    if cmp -s "${sdk}" "${mp}"; then
        echo "result: identical"
    else
        echo "result: different"
    fi
    echo
done

TMP_DIFF="$(mktemp)"
trap 'rm -f "${TMP_DIFF}"' EXIT

diff -qr \
    -x fd \
    -x stdin \
    -x stdout \
    -x stderr \
    -x log \
    -x mtab \
    -x resolv.conf \
    "${SDK_DIR}/target" "${MP_DIR}/target" > "${TMP_DIFF}" 2>/dev/null || true

echo "== Target Tree Summary =="
echo "only in sdk: $(grep -c "^Only in ${SDK_DIR}/target" "${TMP_DIFF}" || true)"
echo "only in myplatform: $(grep -c "^Only in ${MP_DIR}/target" "${TMP_DIFF}" || true)"
echo "files differ: $(grep -c '^Files ' "${TMP_DIFF}" || true)"
echo
echo "== Sample Differences =="
sed -n '1,40p' "${TMP_DIFF}" || true
