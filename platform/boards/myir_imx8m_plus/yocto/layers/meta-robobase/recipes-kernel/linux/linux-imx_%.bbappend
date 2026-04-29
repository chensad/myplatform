FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append = " \
    file://0001-myir-imx8mp-enable-cm7-remoteproc.patch \
    file://0002-remoteproc-add-robobase-cm7-boot-debug-logs.patch \
"
