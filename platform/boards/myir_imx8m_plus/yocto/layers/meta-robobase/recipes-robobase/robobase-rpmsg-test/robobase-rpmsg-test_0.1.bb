SUMMARY = "RoboBase RPMsg TTY echo test tool"
DESCRIPTION = "User-space test utility for the MYD-JX8MP CM7 RPMsg tty echo link"
LICENSE = "CLOSED"

SRC_URI = "file://robobase-rpmsg-test.c"

S = "${WORKDIR}"

ROBOBASE_COMMON_INCLUDE := "${THISDIR}/../../../../../../../common/include"

do_compile() {
    ${CC} ${CFLAGS} -I${ROBOBASE_COMMON_INCLUDE} ${LDFLAGS} robobase-rpmsg-test.c -o robobase-rpmsg-test
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 robobase-rpmsg-test ${D}${bindir}/robobase-rpmsg-test
}
