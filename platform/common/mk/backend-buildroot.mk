BUILDROOT_SRC := $(if $(wildcard $(MODEL_THIRD_PARTY_BUILDROOT_DIR)/Makefile),$(MODEL_THIRD_PARTY_BUILDROOT_DIR),$(LEGACY_BUILDROOT_DIR))
KERNEL_SRC := $(if $(wildcard $(MODEL_THIRD_PARTY_KERNEL_DIR)),$(MODEL_THIRD_PARTY_KERNEL_DIR),$(LEGACY_KERNEL_DIR))
UBOOT_SRC := $(if $(wildcard $(MODEL_THIRD_PARTY_UBOOT_DIR)),$(MODEL_THIRD_PARTY_UBOOT_DIR),$(LEGACY_UBOOT_DIR))

BUILD_OUTPUT_DIR := $(BUILD_OUTPUT_BASE)/$(BOARD_NAME)/$(OUTPUT_TAG)
BUILDROOT_OUTPUT_DIR := $(BUILD_OUTPUT_DIR)/buildroot
BUILDROOT_MERGED_DEFCONFIG := $(BUILDROOT_OUTPUT_DIR)/merged_defconfig
DOWNLOAD_DIR := $(if $(wildcard $(CACHED_DOWNLOAD_DIR)),$(CACHED_DOWNLOAD_DIR),$(BUILD_DOWNLOADS_DIR))

APP_TOOLCHAIN_HOST_DIR ?= $(BUILDROOT_OUTPUT_DIR)/$(MODEL_TOOLCHAIN_HOST_SUBDIR)
APP_TOOLCHAIN_BINDIR := $(BUILDROOT_OUTPUT_DIR)/$(MODEL_TOOLCHAIN_BINDIR_SUBDIR)
APP_TOOLCHAIN_SYSROOT ?= $(BUILDROOT_OUTPUT_DIR)/$(MODEL_TOOLCHAIN_SYSROOT_SUBDIR)
APP_CROSS_COMPILE ?= $(APP_TOOLCHAIN_BINDIR)/$(MODEL_TOOLCHAIN_PREFIX)-
APP_TARGET_DIR ?= $(BUILDROOT_OUTPUT_DIR)/target
APP_TOOLCHAIN_HINT ?= build the Buildroot toolchain first, e.g. make BOARD=$(BOARD) buildroot

IMAGE_TARGET := buildroot
ALL_TARGETS := buildroot app

.PHONY: backend-help backend-vars prepare-buildroot-tree prepare-buildroot-defconfig buildroot linux uboot busybox

backend-help:
	@printf '%s\n' \
		'' \
		'buildroot backend targets:' \
		'  buildroot  build the complete Buildroot image' \
		'  linux      rebuild Linux through Buildroot' \
		'  uboot      rebuild U-Boot through Buildroot' \
		'  busybox    rebuild BusyBox through Buildroot'

backend-vars:
	@printf '%s\n' \
		'BUILDROOT_SRC=$(BUILDROOT_SRC)' \
		'KERNEL_SRC=$(KERNEL_SRC)' \
		'UBOOT_SRC=$(UBOOT_SRC)' \
		'BUILD_OUTPUT_DIR=$(BUILD_OUTPUT_DIR)' \
		'BUILDROOT_OUTPUT_DIR=$(BUILDROOT_OUTPUT_DIR)' \
		'BUILDROOT_MERGED_DEFCONFIG=$(BUILDROOT_MERGED_DEFCONFIG)' \
		'DOWNLOAD_DIR=$(DOWNLOAD_DIR)'

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
