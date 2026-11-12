################################################################################
#
# fakeroot
#
################################################################################

# fakeroot 1.25.3 does not build against a current glibc. The wrapper for
# stat64 takes a "struct stat64 *" and the glibc headers hand out a
# "struct stat *", so the build stops with
#
#   error: expected 'struct stat64 *' but argument is of type 'struct stat *'
#
# 1.37.2 handles both.
FAKEROOT_VERSION = 1.37.2
FAKEROOT_SOURCE = fakeroot_$(FAKEROOT_VERSION).orig.tar.gz
FAKEROOT_SITE = https://snapshot.debian.org/archive/debian/20260401T000000Z/pool/main/f/fakeroot

HOST_FAKEROOT_DEPENDENCIES = host-acl
# Force capabilities detection off
# For now these are process capabilities (faked) rather than file
# so they're of no real use
HOST_FAKEROOT_CONF_ENV = \
	ac_cv_header_sys_capability_h=no \
	ac_cv_func_capset=no
FAKEROOT_LICENSE = GPL-3.0+
FAKEROOT_LICENSE_FILES = COPYING

$(eval $(host-autotools-package))
