################################################################################
#
# libubootenv
#
################################################################################

# v0.3.8 is the current release. It provides libuboot_read_config_ext(),
# libuboot_get_namespace() and libuboot_namespace_from_dt(), which swupdate
# 2026.05.1 needs. The old commit e663439e only had libuboot_read_config()
# and libuboot_getname(), so swupdate failed to link.
LIBUBOOTENV_VERSION = v0.3.8
LIBUBOOTENV_SITE = $(call github,sbabic,libubootenv,$(LIBUBOOTENV_VERSION))
LIBUBOOTENV_LICENSE = LGPL-2.1
LIBUBOOTENV_LICENSE_FILES = LICENSES/LGPL-2.1-or-later.txt
LIBUBOOTENV_INSTALL_STAGING = YES
LIBUBOOTENV_DEPENDENCIES = zlib

# The image has no YAML support. Without this the build fails on the missing
# libyaml, and the configuration files are plain text anyway.
LIBUBOOTENV_CONF_OPTS += -DNO_YML_SUPPORT=1

$(eval $(cmake-package))
