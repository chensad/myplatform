#
# Host-side compatibility overrides carried over from the legacy SDK.
# These are not target BSP features; they exist to keep old Buildroot
# packages building on a newer host toolchain/glibc stack.
#
define HOST_M4_FIX_SIGSTKSZ
	$(SED) 's/^#elif HAVE_LIBSIGSEGV && SIGSTKSZ < 16384/#elif HAVE_LIBSIGSEGV/' $(@D)/lib/c-stack.c
endef

HOST_M4_POST_PATCH_HOOKS += HOST_M4_FIX_SIGSTKSZ

define HOST_FAKEROOT_FIX_STAT_VER
	awk '1; /#include "communicate.h"/ && !done {print "#ifndef _STAT_VER"; print "#define _STAT_VER 0"; print "#endif"; done=1}' \
		$(@D)/libfakeroot.c > $(@D)/libfakeroot.c.fixed
	mv $(@D)/libfakeroot.c.fixed $(@D)/libfakeroot.c
endef

HOST_FAKEROOT_POST_PATCH_HOOKS += HOST_FAKEROOT_FIX_STAT_VER

define HOST_FAKEROOT_USE_SYSTEM_SYSV
	rm -f $(HOST_DIR)/bin/fakeroot $(HOST_DIR)/bin/faked
	ln -sf /usr/bin/fakeroot-sysv $(HOST_DIR)/bin/fakeroot
	ln -sf /usr/bin/faked-sysv $(HOST_DIR)/bin/faked
	rm -f $(HOST_DIR)/lib/libfakeroot.so $(HOST_DIR)/lib/libfakeroot-0.so
	ln -sf /usr/lib/x86_64-linux-gnu/libfakeroot/libfakeroot-sysv.so $(HOST_DIR)/lib/libfakeroot.so
	ln -sf /usr/lib/x86_64-linux-gnu/libfakeroot/libfakeroot-0.so $(HOST_DIR)/lib/libfakeroot-0.so
endef

HOST_FAKEROOT_POST_INSTALL_HOOKS += HOST_FAKEROOT_USE_SYSTEM_SYSV

define HOST_LIBGLIB2_DISABLE_LIBELF_PROBE
	$(SED) 's/^libelf = dependency('"'"'libelf'"'"'.*/libelf = []/' $(@D)/gio/meson.build
	$(SED) 's/^if libelf.found()/if false/' $(@D)/gio/meson.build
endef

HOST_LIBGLIB2_POST_PATCH_HOOKS += HOST_LIBGLIB2_DISABLE_LIBELF_PROBE

# host-gdb 8.2.1 enables the legacy ARM simulator by default.
# The simulator is not needed for target image generation.
HOST_GDB_CONF_OPTS += --disable-sim

define QT5BASE_FIX_GCC13_LIMITS
	awk '1; /^#include <string.h>$$/ && !done {print "#include <limits>"; done=1}' \
		$(@D)/src/corelib/global/qendian.h > $(@D)/src/corelib/global/qendian.h.fixed
	mv $(@D)/src/corelib/global/qendian.h.fixed $(@D)/src/corelib/global/qendian.h
	awk '1; /^#include <QtCore\/qbytearray.h>$$/ && !done {print "#include <limits>"; done=1}' \
		$(@D)/src/corelib/tools/qbytearraymatcher.h > $(@D)/src/corelib/tools/qbytearraymatcher.h.fixed
	mv $(@D)/src/corelib/tools/qbytearraymatcher.h.fixed $(@D)/src/corelib/tools/qbytearraymatcher.h
	awk '1; /^#include <QtCore\/qstringview.h>$$/ && !done {print "#include <limits>"; done=1}' \
		$(@D)/src/tools/moc/generator.cpp > $(@D)/src/tools/moc/generator.cpp.fixed
	mv $(@D)/src/tools/moc/generator.cpp.fixed $(@D)/src/tools/moc/generator.cpp
endef

QT5BASE_POST_PATCH_HOOKS += QT5BASE_FIX_GCC13_LIMITS

define QT5DECLARATIVE_FIX_GCC13_LIMITS
	awk '1; /^#include <private\/qv4global_p.h>$$/ && !done {print "#include <limits>"; done=1}' \
		$(@D)/src/qml/jsruntime/qv4propertykey_p.h > $(@D)/src/qml/jsruntime/qv4propertykey_p.h.fixed
	mv $(@D)/src/qml/jsruntime/qv4propertykey_p.h.fixed $(@D)/src/qml/jsruntime/qv4propertykey_p.h
endef

QT5DECLARATIVE_POST_PATCH_HOOKS += QT5DECLARATIVE_FIX_GCC13_LIMITS
