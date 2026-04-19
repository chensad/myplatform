SHELL := /bin/bash

ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

NEEDS_BOARD_CONTEXT := $(if $(BOARD),1,$(if $(strip $(filter-out help,$(MAKECMDGOALS))),1,))

ifeq ($(NEEDS_BOARD_CONTEXT),1)
ifndef BOARD
$(error BOARD is required. Example: make BOARD=imx6ull_100ask_pro image)
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

BUILD_OUTPUT_BASE ?= $(ROOT_DIR)build/out
BUILD_DOWNLOADS_DIR ?= $(ROOT_DIR)build/downloads
BUILD_CCACHE_DIR ?= $(ROOT_DIR)build/ccache
BUILD_LOGS_DIR ?= $(ROOT_DIR)build/logs
BUILD_SSTATE_DIR ?= $(ROOT_DIR)build/sstate-cache

PUBLIC_APPS_DIR := $(ROOT_DIR)apps/public
PRIVATE_APPS_DIR := $(ROOT_DIR)apps/private

BUILD_BACKEND ?= $(if $(MODEL_BUILD_BACKEND),$(MODEL_BUILD_BACKEND),$(if $(BOARD_BUILD_BACKEND),$(BOARD_BUILD_BACKEND),buildroot))
BACKEND_MK := $(ROOT_DIR)platform/common/mk/backend-$(BUILD_BACKEND).mk
ifeq ($(wildcard $(BACKEND_MK)),)
$(error Unsupported build backend '$(BUILD_BACKEND)'; missing $(BACKEND_MK))
endif

APP_CPPFLAGS ?= $(strip $(MODEL_APP_CPPFLAGS) $(BOARD_APP_CPPFLAGS))
APP_TOOLCHAIN_HINT ?= configure APP_CROSS_COMPILE and APP_TOOLCHAIN_SYSROOT in the model or on the command line.

include $(BACKEND_MK)

ifneq ($(strip $(MODEL_APP_CROSS_COMPILE)),)
APP_CROSS_COMPILE := $(MODEL_APP_CROSS_COMPILE)
endif
ifneq ($(strip $(MODEL_APP_TOOLCHAIN_HOST_DIR)),)
APP_TOOLCHAIN_HOST_DIR := $(MODEL_APP_TOOLCHAIN_HOST_DIR)
endif
ifneq ($(strip $(MODEL_APP_TOOLCHAIN_SYSROOT)),)
APP_TOOLCHAIN_SYSROOT := $(MODEL_APP_TOOLCHAIN_SYSROOT)
endif
ifneq ($(strip $(MODEL_APP_TARGET_DIR)),)
APP_TARGET_DIR := $(MODEL_APP_TARGET_DIR)
endif

IMAGE_TARGET ?= image
ALL_TARGETS ?= $(IMAGE_TARGET) app
endif

.PHONY: help vars all image app app-clean

help:
	@printf '%s\n' \
		'usage:' \
		'  make BOARD=<board> [OUTPUT_TAG=<tag>] <target>' \
		'  make BOARD=<board> app [PUBLIC_APPS="<apps>"] [PRIVATE_APPS="<apps>"]' \
		'' \
		'common targets:' \
		'  all        build the board default target set' \
		'  image      build the active backend image target' \
		'  app        build configured public/private apps' \
		'  app-clean  clean configured public/private app outputs' \
		'  vars       print resolved board/model/backend variables' \
		'  help       show this help text' \
		'' \
		'notes:' \
		'  build backend is selected by MODEL_BUILD_BACKEND or BOARD_BUILD_BACKEND' \
		'  board directories do not need to share the same internal layout' \
		'' \
		'examples:' \
		'  make BOARD=imx6ull_100ask_pro image' \
		'  make BOARD=imx6ull_100ask_pro buildroot' \
		'  make BOARD=myir_imx8m_plus yocto' \
		'  make BOARD=myir_imx8m_plus sdk'
ifeq ($(NEEDS_BOARD_CONTEXT),1)
	@$(MAKE) --no-print-directory BOARD="$(BOARD)" MODEL_CONFIG="$(MODEL_CONFIG)" backend-help
endif

vars:
	@printf '%s\n' \
		'BOARD=$(BOARD)' \
		'BOARD_NAME=$(BOARD_NAME)' \
		'MODEL_NAME=$(MODEL_NAME)' \
		'MODEL_CONFIG=$(MODEL_CONFIG)' \
		'OUTPUT_TAG=$(OUTPUT_TAG)' \
		'BUILD_BACKEND=$(BUILD_BACKEND)' \
		'PUBLIC_APPS=$(PUBLIC_APPS)' \
		'PRIVATE_APPS=$(PRIVATE_APPS)' \
		'PUBLIC_APPS_DIR=$(PUBLIC_APPS_DIR)' \
		'PRIVATE_APPS_DIR=$(PRIVATE_APPS_DIR)' \
		'APP_CPPFLAGS=$(APP_CPPFLAGS)' \
		'APP_CROSS_COMPILE=$(APP_CROSS_COMPILE)' \
		'APP_TOOLCHAIN_HOST_DIR=$(APP_TOOLCHAIN_HOST_DIR)' \
		'APP_TOOLCHAIN_SYSROOT=$(APP_TOOLCHAIN_SYSROOT)' \
		'APP_TARGET_DIR=$(APP_TARGET_DIR)'
	@$(MAKE) --no-print-directory BOARD="$(BOARD)" MODEL_CONFIG="$(MODEL_CONFIG)" backend-vars

all: $(ALL_TARGETS)

image: $(IMAGE_TARGET)

app:
	@if [[ -z "$(APP_CROSS_COMPILE)" ]]; then \
		echo "app toolchain is not configured for backend '$(BUILD_BACKEND)'" >&2; \
		echo "$(APP_TOOLCHAIN_HINT)" >&2; \
		exit 1; \
	fi
	@test -x "$(APP_CROSS_COMPILE)gcc" || { \
		echo "missing cross compiler: $(APP_CROSS_COMPILE)gcc" >&2; \
		echo "$(APP_TOOLCHAIN_HINT)" >&2; \
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
	$(MAKE) -C "$(PUBLIC_APPS_DIR)" clean APPS="$(PUBLIC_APPS)"
	$(MAKE) -C "$(PRIVATE_APPS_DIR)" clean APPS="$(PRIVATE_APPS)"
