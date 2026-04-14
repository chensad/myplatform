SHELL := /bin/bash

ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

KNOWN_COMPONENTS := all app app-clean buildroot linux uboot busybox vars help

ifeq ($(filter help,$(MAKECMDGOALS)),)
ifndef BOARD
$(error BOARD is required. Example: make BOARD=imx6ull_100ask_pro buildroot)
endif

BOARD_DIR := $(ROOT_DIR)platform/boards/$(BOARD)
ifeq ($(wildcard $(BOARD_DIR)/board.mk),)
$(error Unknown board '$(BOARD)'; missing $(BOARD_DIR)/board.mk)
endif

include $(BOARD_DIR)/board.mk

MODEL_CONFIG ?= $(BOARD_DIR)/model.mk
ifeq ($(wildcard $(MODEL_CONFIG)),)
$(error Missing model config: $(MODEL_CONFIG))
endif

include $(MODEL_CONFIG)

OUTPUT_TAG ?= $(MODEL_OUTPUT_TAG)
PUBLIC_APPS ?= $(MODEL_PUBLIC_APPS)
PRIVATE_APPS ?= $(MODEL_PRIVATE_APPS)

BUILDROOT_SRC := $(if $(wildcard $(MODEL_THIRD_PARTY_BUILDROOT_DIR)/Makefile),$(MODEL_THIRD_PARTY_BUILDROOT_DIR),$(LEGACY_BUILDROOT_DIR))
KERNEL_SRC := $(if $(wildcard $(MODEL_THIRD_PARTY_KERNEL_DIR)),$(MODEL_THIRD_PARTY_KERNEL_DIR),$(LEGACY_KERNEL_DIR))
UBOOT_SRC := $(if $(wildcard $(MODEL_THIRD_PARTY_UBOOT_DIR)),$(MODEL_THIRD_PARTY_UBOOT_DIR),$(LEGACY_UBOOT_DIR))

BUILD_OUTPUT_DIR := $(BUILD_OUTPUT_BASE)/$(BOARD_NAME)/$(OUTPUT_TAG)
BUILDROOT_OUTPUT_DIR := $(BUILD_OUTPUT_DIR)/buildroot
BUILDROOT_MERGED_DEFCONFIG := $(BUILDROOT_OUTPUT_DIR)/merged_defconfig
DOWNLOAD_DIR := $(if $(wildcard $(CACHED_DOWNLOAD_DIR)),$(CACHED_DOWNLOAD_DIR),$(BUILD_DOWNLOADS_DIR))

PUBLIC_APPS_DIR := $(ROOT_DIR)apps/public
PRIVATE_APPS_DIR := $(ROOT_DIR)apps/private
APP_CPPFLAGS := $(MODEL_APP_CPPFLAGS)
APP_TOOLCHAIN_HOST_DIR := $(BUILDROOT_OUTPUT_DIR)/$(MODEL_TOOLCHAIN_HOST_SUBDIR)
APP_TOOLCHAIN_BINDIR := $(BUILDROOT_OUTPUT_DIR)/$(MODEL_TOOLCHAIN_BINDIR_SUBDIR)
APP_TOOLCHAIN_SYSROOT := $(BUILDROOT_OUTPUT_DIR)/$(MODEL_TOOLCHAIN_SYSROOT_SUBDIR)
APP_CROSS_COMPILE := $(APP_TOOLCHAIN_BINDIR)/$(MODEL_TOOLCHAIN_PREFIX)-
APP_TARGET_DIR := $(BUILDROOT_OUTPUT_DIR)/target
endif

.PHONY: help vars all app app-clean buildroot linux uboot busybox prepare-buildroot-tree prepare-buildroot-defconfig

help:
	@printf '%s\n' \
		'usage:' \
		'  make BOARD=<board> [OUTPUT_TAG=<tag>] <target>' \
		'  make BOARD=<board> [OUTPUT_TAG=<tag>] app [PUBLIC_APPS="<apps>"] [PRIVATE_APPS="<apps>"]' \
		'' \
		'targets:' \
		'  all        build configured public/private apps and Buildroot image' \
		'  app        build configured public/private apps with board/model macros' \
		'  app-clean  clean configured public/private app outputs' \
		'  buildroot  build complete Buildroot image' \
		'  linux      rebuild Linux through Buildroot' \
		'  uboot      rebuild U-Boot through Buildroot' \
		'  busybox    rebuild BusyBox through Buildroot' \
		'  vars       print resolved board/model variables' \
		'' \
		'examples:' \
		'  make BOARD=imx6ull_100ask_pro buildroot' \
		'  make BOARD=imx6ull_100ask_pro app' \
		'  make BOARD=imx6ull_100ask_pro app-clean' \
		'  make BOARD=imx6ull_100ask_pro app PUBLIC_APPS="app_demo"' \
		'  make BOARD=imx6ull_100ask_pro app PRIVATE_APPS="detect_gps"' \
		'  make BOARD=imx6ull_100ask_pro linux' \
		'  make BOARD=imx6ull_100ask_pro busybox'

vars:
	@printf '%s\n' \
		'BOARD_NAME=$(BOARD_NAME)' \
		'MODEL_NAME=$(MODEL_NAME)' \
		'OUTPUT_TAG=$(OUTPUT_TAG)' \
		'BUILDROOT_SRC=$(BUILDROOT_SRC)' \
		'KERNEL_SRC=$(KERNEL_SRC)' \
		'UBOOT_SRC=$(UBOOT_SRC)' \
		'BUILDROOT_OUTPUT_DIR=$(BUILDROOT_OUTPUT_DIR)' \
		'PUBLIC_APPS=$(PUBLIC_APPS)' \
		'PRIVATE_APPS=$(PRIVATE_APPS)' \
		'PUBLIC_APPS_DIR=$(PUBLIC_APPS_DIR)' \
		'PRIVATE_APPS_DIR=$(PRIVATE_APPS_DIR)' \
		'APP_CPPFLAGS=$(APP_CPPFLAGS)' \
		'APP_CROSS_COMPILE=$(APP_CROSS_COMPILE)' \
		'APP_TOOLCHAIN_SYSROOT=$(APP_TOOLCHAIN_SYSROOT)' \
		'MODEL_KERNEL_DTS_NAME=$(MODEL_KERNEL_DTS_NAME)' \
		'MODEL_KERNEL_INTREE_DTS_NAMES=$(MODEL_KERNEL_INTREE_DTS_NAMES)' \
		'MODEL_KERNEL_CUSTOM_DTS_PATHS=$(MODEL_KERNEL_CUSTOM_DTS_PATHS)'

all: buildroot app

app:
	@test -x "$(APP_CROSS_COMPILE)gcc" || { \
		echo "missing cross compiler: $(APP_CROSS_COMPILE)gcc" >&2; \
		echo "build the Buildroot toolchain first, e.g. make BOARD=$(BOARD) buildroot" >&2; \
		exit 1; \
	}
	$(MAKE) -C "$(PUBLIC_APPS_DIR)" \
		APPS="$(PUBLIC_APPS)" \
		CROSS_COMPILE="$(APP_CROSS_COMPILE)" \
		HOST_DIR="$(APP_TOOLCHAIN_HOST_DIR)" \
		STAGING_DIR="$(APP_TOOLCHAIN_SYSROOT)" \
		SYSROOT="$(APP_TOOLCHAIN_SYSROOT)" \
		TARGET_DIR="$(APP_TARGET_DIR)" \
		CPPFLAGS="$(APP_CPPFLAGS)"
	$(MAKE) -C "$(PRIVATE_APPS_DIR)" \
		APPS="$(PRIVATE_APPS)" \
		CROSS_COMPILE="$(APP_CROSS_COMPILE)" \
		HOST_DIR="$(APP_TOOLCHAIN_HOST_DIR)" \
		STAGING_DIR="$(APP_TOOLCHAIN_SYSROOT)" \
		SYSROOT="$(APP_TOOLCHAIN_SYSROOT)" \
		TARGET_DIR="$(APP_TARGET_DIR)" \
		CPPFLAGS="$(APP_CPPFLAGS)"

app-clean:
	$(MAKE) -C "$(PUBLIC_APPS_DIR)" \
		clean \
		APPS="$(PUBLIC_APPS)"
	$(MAKE) -C "$(PRIVATE_APPS_DIR)" \
		clean \
		APPS="$(PRIVATE_APPS)"

prepare-buildroot-tree:
	@mkdir -p "$(BUILDROOT_OUTPUT_DIR)" "$(DOWNLOAD_DIR)" "$(BUILD_LOGS_DIR)" "$(BUILD_CCACHE_DIR)"
	@ln -snf "$(BOARD_BUILDROOT_BOARD_DIR)" "$(BUILDROOT_OUTPUT_DIR)/board"
	@ln -snf "$(BOARD_BUILDROOT_BOARD_DIR)/local.mk" "$(BUILDROOT_OUTPUT_DIR)/local.mk"

prepare-buildroot-defconfig: prepare-buildroot-tree
	@/bin/bash -eu -c '\
		emit_config() { \
			local config_file="$$1"; \
			local config_dir line; \
			config_dir="$$(dirname "$$config_file")"; \
			while IFS= read -r line || [[ -n "$$line" ]]; do \
				if [[ "$$line" =~ ^#include[[:space:]]+\"([^\"]+)\"$$ ]]; then \
					emit_config "$$config_dir/$${BASH_REMATCH[1]}"; \
				else \
					printf "%s\n" "$$line"; \
				fi; \
			done < "$$config_file"; \
		}; \
		emit_config "$(BOARD_BUILDROOT_DEFCONFIG)" > "$(BUILDROOT_MERGED_DEFCONFIG)"; \
		for extra in $(MODEL_BUILDROOT_EXTRA_CONFIGS); do \
			printf "\n" >> "$(BUILDROOT_MERGED_DEFCONFIG)"; \
			cat "$$extra" >> "$(BUILDROOT_MERGED_DEFCONFIG)"; \
		done; \
		printf "\nBR2_LINUX_KERNEL_INTREE_DTS_NAME=\"%s\"\n" "$(MODEL_KERNEL_INTREE_DTS_NAMES)" >> "$(BUILDROOT_MERGED_DEFCONFIG)"; \
		printf "BR2_LINUX_KERNEL_CUSTOM_DTS_PATH=\"%s\"\n" "$(MODEL_KERNEL_CUSTOM_DTS_PATHS)" >> "$(BUILDROOT_MERGED_DEFCONFIG)"'

buildroot: prepare-buildroot-defconfig
	$(MAKE) -C "$(BUILDROOT_SRC)" \
		O="$(BUILDROOT_OUTPUT_DIR)" \
		BR2_EXTERNAL="$(BOARD_BUILDROOT_EXTERNAL_DIR)" \
		BR2_DEFCONFIG="$(BUILDROOT_MERGED_DEFCONFIG)" \
		BR2_DL_DIR="$(DOWNLOAD_DIR)" \
		defconfig
	$(MAKE) -C "$(BUILDROOT_SRC)" \
		O="$(BUILDROOT_OUTPUT_DIR)" \
		BR2_EXTERNAL="$(BOARD_BUILDROOT_EXTERNAL_DIR)" \
		BR2_DL_DIR="$(DOWNLOAD_DIR)" \
		LINUX_OVERRIDE_SRCDIR="$(KERNEL_SRC)" \
		LINUX_HEADERS_OVERRIDE_SRCDIR="$(KERNEL_SRC)" \
		UBOOT_OVERRIDE_SRCDIR="$(UBOOT_SRC)" \
		MYPLATFORM_APP_CPPFLAGS="$(APP_CPPFLAGS)" \
		all

linux: prepare-buildroot-defconfig
	$(MAKE) -C "$(BUILDROOT_SRC)" \
		O="$(BUILDROOT_OUTPUT_DIR)" \
		BR2_EXTERNAL="$(BOARD_BUILDROOT_EXTERNAL_DIR)" \
		BR2_DEFCONFIG="$(BUILDROOT_MERGED_DEFCONFIG)" \
		BR2_DL_DIR="$(DOWNLOAD_DIR)" \
		defconfig
	$(MAKE) -C "$(BUILDROOT_SRC)" \
		O="$(BUILDROOT_OUTPUT_DIR)" \
		BR2_EXTERNAL="$(BOARD_BUILDROOT_EXTERNAL_DIR)" \
		BR2_DL_DIR="$(DOWNLOAD_DIR)" \
		LINUX_OVERRIDE_SRCDIR="$(KERNEL_SRC)" \
		LINUX_HEADERS_OVERRIDE_SRCDIR="$(KERNEL_SRC)" \
		UBOOT_OVERRIDE_SRCDIR="$(UBOOT_SRC)" \
		MYPLATFORM_APP_CPPFLAGS="$(APP_CPPFLAGS)" \
		linux-rebuild

uboot: prepare-buildroot-defconfig
	$(MAKE) -C "$(BUILDROOT_SRC)" \
		O="$(BUILDROOT_OUTPUT_DIR)" \
		BR2_EXTERNAL="$(BOARD_BUILDROOT_EXTERNAL_DIR)" \
		BR2_DEFCONFIG="$(BUILDROOT_MERGED_DEFCONFIG)" \
		BR2_DL_DIR="$(DOWNLOAD_DIR)" \
		defconfig
	$(MAKE) -C "$(BUILDROOT_SRC)" \
		O="$(BUILDROOT_OUTPUT_DIR)" \
		BR2_EXTERNAL="$(BOARD_BUILDROOT_EXTERNAL_DIR)" \
		BR2_DL_DIR="$(DOWNLOAD_DIR)" \
		LINUX_OVERRIDE_SRCDIR="$(KERNEL_SRC)" \
		LINUX_HEADERS_OVERRIDE_SRCDIR="$(KERNEL_SRC)" \
		UBOOT_OVERRIDE_SRCDIR="$(UBOOT_SRC)" \
		MYPLATFORM_APP_CPPFLAGS="$(APP_CPPFLAGS)" \
		uboot-rebuild

busybox: prepare-buildroot-defconfig
	$(MAKE) -C "$(BUILDROOT_SRC)" \
		O="$(BUILDROOT_OUTPUT_DIR)" \
		BR2_EXTERNAL="$(BOARD_BUILDROOT_EXTERNAL_DIR)" \
		BR2_DEFCONFIG="$(BUILDROOT_MERGED_DEFCONFIG)" \
		BR2_DL_DIR="$(DOWNLOAD_DIR)" \
		defconfig
	$(MAKE) -C "$(BUILDROOT_SRC)" \
		O="$(BUILDROOT_OUTPUT_DIR)" \
		BR2_EXTERNAL="$(BOARD_BUILDROOT_EXTERNAL_DIR)" \
		BR2_DL_DIR="$(DOWNLOAD_DIR)" \
		LINUX_OVERRIDE_SRCDIR="$(KERNEL_SRC)" \
		LINUX_HEADERS_OVERRIDE_SRCDIR="$(KERNEL_SRC)" \
		UBOOT_OVERRIDE_SRCDIR="$(UBOOT_SRC)" \
		MYPLATFORM_APP_CPPFLAGS="$(APP_CPPFLAGS)" \
		busybox-rebuild
