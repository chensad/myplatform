APPS ?=
CROSS_COMPILE ?=
HOST_DIR ?=
STAGING_DIR ?=
SYSROOT ?=
TARGET_DIR ?=
CPPFLAGS ?=

.PHONY: all clean check-apps

all: check-apps
	@set -eu; \
	for app in $(APPS); do \
		echo "==> build public app: $$app"; \
		$(MAKE) -C "$$app" \
			CROSS_COMPILE="$(CROSS_COMPILE)" \
			HOST_DIR="$(HOST_DIR)" \
			STAGING_DIR="$(STAGING_DIR)" \
			SYSROOT="$(SYSROOT)" \
			TARGET_DIR="$(TARGET_DIR)" \
			CPPFLAGS="$(CPPFLAGS)"; \
	done

clean:
	@set -eu; \
	for app in $(APPS); do \
		test -d "$$app" || continue; \
		$(MAKE) -C "$$app" clean; \
	done

check-apps:
	@set -eu; \
	for app in $(APPS); do \
		test -f "$$app/Makefile" || { \
			echo "public app not found: $$app" >&2; \
			exit 1; \
		}; \
	done
