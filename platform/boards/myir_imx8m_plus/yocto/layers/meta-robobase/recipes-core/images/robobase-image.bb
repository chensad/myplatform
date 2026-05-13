SUMMARY = "RoboBase image for MYIR i.MX8MP"
LICENSE = "MIT"

require ${BSPDIR}/sources/meta-myir/meta-sdk/recipes-fsl/images/myir-image-full.bb

DESCRIPTION = "Custom RoboBase image based on MYIR full image"

IMAGE_INSTALL_append = " test-yocto robobase-rpmsg-test robobase-m7-firmware robobase-m7-services"
