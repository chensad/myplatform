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

define HOST_LIBGLIB2_DISABLE_LIBELF_PROBE
	$(SED) 's/^libelf = dependency('"'"'libelf'"'"'.*/libelf = []/' $(@D)/gio/meson.build
	$(SED) 's/^if libelf.found()/if false/' $(@D)/gio/meson.build
endef

HOST_LIBGLIB2_POST_PATCH_HOOKS += HOST_LIBGLIB2_DISABLE_LIBELF_PROBE

# host-gdb 8.2.1 enables the legacy ARM simulator by default.
# The simulator is not needed for target image generation.
HOST_GDB_CONF_OPTS += --disable-sim
