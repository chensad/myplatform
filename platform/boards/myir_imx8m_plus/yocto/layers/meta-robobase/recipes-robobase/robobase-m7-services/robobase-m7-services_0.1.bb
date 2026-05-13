SUMMARY = "RoboBase M7 remoteproc and RPMsg TTY systemd services"
DESCRIPTION = "Installs startup scripts and systemd units to load the CM7 firmware and RPMsg TTY endpoint on boot"
LICENSE = "CLOSED"

SRC_URI = " \
    file://robobase-m7-start \
    file://robobase-m7-stop \
    file://robobase-rpmsg-tty-setup \
    file://robobase-m7.default \
    file://robobase-m7.service \
    file://robobase-rpmsg-tty.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE_${PN} = "robobase-m7.service robobase-rpmsg-tty.service"
SYSTEMD_AUTO_ENABLE_${PN} = "enable"

RDEPENDS_${PN} += "kmod robobase-m7-firmware"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/robobase-m7-start ${D}${bindir}/robobase-m7-start
    install -m 0755 ${WORKDIR}/robobase-m7-stop ${D}${bindir}/robobase-m7-stop
    install -m 0755 ${WORKDIR}/robobase-rpmsg-tty-setup ${D}${bindir}/robobase-rpmsg-tty-setup

    install -d ${D}${sysconfdir}/default
    install -m 0644 ${WORKDIR}/robobase-m7.default ${D}${sysconfdir}/default/robobase-m7

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/robobase-m7.service ${D}${systemd_system_unitdir}/robobase-m7.service
    install -m 0644 ${WORKDIR}/robobase-rpmsg-tty.service ${D}${systemd_system_unitdir}/robobase-rpmsg-tty.service
}

FILES_${PN} += " \
    ${bindir}/robobase-m7-start \
    ${bindir}/robobase-m7-stop \
    ${bindir}/robobase-rpmsg-tty-setup \
    ${sysconfdir}/default/robobase-m7 \
    ${systemd_system_unitdir}/robobase-m7.service \
    ${systemd_system_unitdir}/robobase-rpmsg-tty.service \
"
