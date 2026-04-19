MODEL_NAME := myir_imx8m_plus
MODEL_BUILD_BACKEND := yocto

MODEL_OUTPUT_TAG := xwayland

MODEL_THIRD_PARTY_YOCTO_DIR := $(ROOT_DIR)third_party/yocto/yocto_5.10.72
MODEL_YOCTO_SETUP_SCRIPT := $(MODEL_THIRD_PARTY_YOCTO_DIR)/sources/meta-myir/tools/myir-setup-release.sh
MODEL_YOCTO_MACHINE := myd-jx8mp
MODEL_YOCTO_DISTRO := fsl-imx-xwayland
MODEL_YOCTO_IMAGE_TARGET := myir-image-full
MODEL_YOCTO_SDK_TARGET := meta-toolchain
MODEL_YOCTO_KERNEL_TARGET := virtual/kernel
MODEL_YOCTO_UBOOT_TARGET := u-boot-imx

MODEL_APP_CPPFLAGS := \
	-DCONFIG_MODEL_MYIR_IMX8M_PLUS=1
