################################################################################
#
# app_demo
#
################################################################################

APP_DEMO_VERSION = 1.0.0
APP_DEMO_SITE = $(TOPDIR)/../apps/public/app_demo
APP_DEMO_SITE_METHOD = local

APP_DEMO_INSTALL_TARGET = YES

define APP_DEMO_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) CC="$(TARGET_CC)" CPPFLAGS="$(MYPLATFORM_APP_CPPFLAGS)" -C $(@D) app_demo
endef

define APP_DEMO_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/app_demo $(TARGET_DIR)/usr/bin/app_demo
endef

$(eval $(generic-package))
