SUMMARY = "RoboBase demo application"
LICENSE = "CLOSED"

SRC_URI = "file://test-yocto.c"

S = "${WORKDIR}"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} test-yocto.c -o test-yocto
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 test-yocto ${D}${bindir}/test-yocto
}
