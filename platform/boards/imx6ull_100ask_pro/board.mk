BOARD_NAME := imx6ull_100ask_pro
BOARD_SOC := imx6ull
BOARD_VENDOR := 100ask

LEGACY_SDK_DIR := $(abspath $(ROOT_DIR)../100ask_imx6ull-sdk)
LEGACY_BUILDROOT_DIR := $(LEGACY_SDK_DIR)/Buildroot_2020.02.x
LEGACY_KERNEL_DIR := $(LEGACY_SDK_DIR)/Linux-4.9.88
LEGACY_UBOOT_DIR := $(LEGACY_SDK_DIR)/Uboot-2017.03

BUILD_OUTPUT_BASE := $(ROOT_DIR)build/out
BUILD_DOWNLOADS_DIR := $(ROOT_DIR)build/downloads
BUILD_CCACHE_DIR := $(ROOT_DIR)build/ccache
BUILD_LOGS_DIR := $(ROOT_DIR)build/logs
CACHED_DOWNLOAD_DIR := $(abspath $(ROOT_DIR)../.cache/100ask-buildroot-dl)

BOARD_BUILDROOT_DEFCONFIG := $(BOARD_DIR)/buildroot/defconfig
BOARD_BUILDROOT_EXTERNAL_DIR := $(BOARD_DIR)/buildroot/external
BOARD_BUILDROOT_BOARD_DIR := $(BOARD_DIR)/buildroot/board
