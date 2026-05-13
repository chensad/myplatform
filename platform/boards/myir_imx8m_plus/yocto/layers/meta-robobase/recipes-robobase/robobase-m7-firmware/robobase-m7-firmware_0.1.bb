SUMMARY = "RoboBase Cortex-M7 firmware image"
DESCRIPTION = "Installs the prebuilt RoboBase CM7 ELF into the Linux firmware directory for remoteproc boot"
LICENSE = "CLOSED"

S = "${WORKDIR}"

ROBOBASE_M7_FIRMWARE ?= "robobase_m7_rpmsg_tty_echo.elf"
ROBOBASE_M7_APP_DIR ?= "${THISDIR}/../../../../../../../../third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only"
ROBOBASE_M7_ELF ?= "${ROBOBASE_M7_APP_DIR}/armgcc/debug/${ROBOBASE_M7_FIRMWARE}"

PACKAGE_ARCH = "${MACHINE_ARCH}"

# The file is an ARM Cortex-M7 firmware ELF, not an A53 Linux userspace binary.
# Keep Yocto from stripping/splitting it with target tools or rejecting its arch.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INSANE_SKIP_${PN} += "arch already-stripped"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    if [ ! -f "${ROBOBASE_M7_ELF}" ]; then
        bbfatal "RoboBase M7 firmware ELF not found: ${ROBOBASE_M7_ELF}. Build the M7 firmware first."
    fi

    install -d ${D}${base_libdir}/firmware
    install -m 0644 ${ROBOBASE_M7_ELF} ${D}${base_libdir}/firmware/${ROBOBASE_M7_FIRMWARE}
}

FILES_${PN} += "${base_libdir}/firmware/${ROBOBASE_M7_FIRMWARE}"
