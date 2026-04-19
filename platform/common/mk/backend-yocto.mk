YOCTO_SRC := $(MODEL_THIRD_PARTY_YOCTO_DIR)
YOCTO_SETUP_SCRIPT := $(if $(wildcard $(MODEL_YOCTO_SETUP_SCRIPT)),$(MODEL_YOCTO_SETUP_SCRIPT),$(YOCTO_SRC)/sources/meta-myir/tools/myir-setup-release.sh)
YOCTO_MACHINE := $(if $(MODEL_YOCTO_MACHINE),$(MODEL_YOCTO_MACHINE),$(BOARD_NAME))
YOCTO_DISTRO := $(if $(MODEL_YOCTO_DISTRO),$(MODEL_YOCTO_DISTRO),fsl-imx-xwayland)
YOCTO_IMAGE_TARGET := $(if $(MODEL_YOCTO_IMAGE_TARGET),$(MODEL_YOCTO_IMAGE_TARGET),core-image-minimal)
YOCTO_SDK_TARGET := $(if $(MODEL_YOCTO_SDK_TARGET),$(MODEL_YOCTO_SDK_TARGET),meta-toolchain)
YOCTO_KERNEL_TARGET := $(if $(MODEL_YOCTO_KERNEL_TARGET),$(MODEL_YOCTO_KERNEL_TARGET),virtual/kernel)
YOCTO_UBOOT_TARGET := $(if $(MODEL_YOCTO_UBOOT_TARGET),$(MODEL_YOCTO_UBOOT_TARGET),u-boot-imx)
YOCTO_EULA := $(if $(MODEL_YOCTO_EULA),$(MODEL_YOCTO_EULA),1)

BUILD_OUTPUT_DIR := $(BUILD_OUTPUT_BASE)/$(BOARD_NAME)/$(OUTPUT_TAG)
YOCTO_BUILD_DIR_ABS := $(BUILD_OUTPUT_DIR)/yocto
YOCTO_BUILD_DIR_REL := $(shell realpath -m --relative-to="$(YOCTO_SRC)" "$(YOCTO_BUILD_DIR_ABS)")
YOCTO_ARTIFACTS_DIR := $(YOCTO_BUILD_DIR_ABS)/tmp/deploy/images/$(YOCTO_MACHINE)
YOCTO_SDK_OUTPUT_DIR := $(YOCTO_BUILD_DIR_ABS)/tmp/deploy/sdk
YOCTO_DOWNLOADS_DIR := $(BUILD_DOWNLOADS_DIR)/yocto
YOCTO_SSTATE_DIR := $(BUILD_SSTATE_DIR)/yocto

APP_TOOLCHAIN_HINT ?= generate and install a Yocto SDK, then pass APP_CROSS_COMPILE/APP_TOOLCHAIN_SYSROOT or define MODEL_APP_* variables.

IMAGE_TARGET := yocto
ALL_TARGETS := yocto

.PHONY: backend-help backend-vars prepare-yocto-env yocto sdk linux uboot

backend-help:
	@printf '%s\n' \
		'' \
		'yocto backend targets:' \
		'  yocto     build the configured Yocto image target' \
		'  linux     build the Yocto kernel target' \
		'  uboot     build the Yocto U-Boot target' \
		'  sdk       generate the Yocto SDK installer'

backend-vars:
	@printf '%s\n' \
		'YOCTO_SRC=$(YOCTO_SRC)' \
		'YOCTO_SETUP_SCRIPT=$(YOCTO_SETUP_SCRIPT)' \
		'YOCTO_MACHINE=$(YOCTO_MACHINE)' \
		'YOCTO_DISTRO=$(YOCTO_DISTRO)' \
		'YOCTO_IMAGE_TARGET=$(YOCTO_IMAGE_TARGET)' \
		'YOCTO_SDK_TARGET=$(YOCTO_SDK_TARGET)' \
		'YOCTO_BUILD_DIR_ABS=$(YOCTO_BUILD_DIR_ABS)' \
		'YOCTO_BUILD_DIR_REL=$(YOCTO_BUILD_DIR_REL)' \
		'YOCTO_ARTIFACTS_DIR=$(YOCTO_ARTIFACTS_DIR)' \
		'YOCTO_DOWNLOADS_DIR=$(YOCTO_DOWNLOADS_DIR)' \
		'YOCTO_SSTATE_DIR=$(YOCTO_SSTATE_DIR)'

prepare-yocto-env:
	@mkdir -p "$(YOCTO_BUILD_DIR_ABS)" "$(YOCTO_DOWNLOADS_DIR)" "$(YOCTO_SSTATE_DIR)"
	@cd "$(YOCTO_SRC)" && \
		export EULA="$(YOCTO_EULA)" DISTRO="$(YOCTO_DISTRO)" MACHINE="$(YOCTO_MACHINE)"; \
		source "$(YOCTO_SETUP_SCRIPT)" -b "$(YOCTO_BUILD_DIR_REL)" >/dev/null; \
		set_conf_var() { \
			local key="$$1"; \
			local value="$$2"; \
			local file="conf/local.conf"; \
			if grep -qE "^$${key}[[:space:]]*[?:+]?=" "$$file"; then \
				sed -i -E "s|^$${key}[[:space:]]*[?:+]?=.*|$${key} = \"$${value}\"|" "$$file"; \
			else \
				printf "%s = \"%s\"\n" "$$key" "$$value" >> "$$file"; \
			fi; \
		}; \
		set_conf_var DL_DIR "$(YOCTO_DOWNLOADS_DIR)"; \
		set_conf_var SSTATE_DIR "$(YOCTO_SSTATE_DIR)"

yocto: prepare-yocto-env
	@cd "$(YOCTO_SRC)" && \
		export EULA="$(YOCTO_EULA)" DISTRO="$(YOCTO_DISTRO)" MACHINE="$(YOCTO_MACHINE)"; \
		source "$(YOCTO_SETUP_SCRIPT)" -b "$(YOCTO_BUILD_DIR_REL)" >/dev/null; \
		bitbake "$(YOCTO_IMAGE_TARGET)"

linux: prepare-yocto-env
	@cd "$(YOCTO_SRC)" && \
		export EULA="$(YOCTO_EULA)" DISTRO="$(YOCTO_DISTRO)" MACHINE="$(YOCTO_MACHINE)"; \
		source "$(YOCTO_SETUP_SCRIPT)" -b "$(YOCTO_BUILD_DIR_REL)" >/dev/null; \
		bitbake "$(YOCTO_KERNEL_TARGET)"

uboot: prepare-yocto-env
	@cd "$(YOCTO_SRC)" && \
		export EULA="$(YOCTO_EULA)" DISTRO="$(YOCTO_DISTRO)" MACHINE="$(YOCTO_MACHINE)"; \
		source "$(YOCTO_SETUP_SCRIPT)" -b "$(YOCTO_BUILD_DIR_REL)" >/dev/null; \
		bitbake "$(YOCTO_UBOOT_TARGET)"

sdk: prepare-yocto-env
	@cd "$(YOCTO_SRC)" && \
		export EULA="$(YOCTO_EULA)" DISTRO="$(YOCTO_DISTRO)" MACHINE="$(YOCTO_MACHINE)"; \
		source "$(YOCTO_SETUP_SCRIPT)" -b "$(YOCTO_BUILD_DIR_REL)" >/dev/null; \
		bitbake -c populate_sdk "$(YOCTO_SDK_TARGET)"
