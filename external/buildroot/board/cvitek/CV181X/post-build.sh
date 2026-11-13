#!/bin/sh

# The core board of the reCamera HQ PoE, the C1-2002, has no wireless
# module. The wifi packages are switched off in the board defconfig and
# the wireless kernel modules are gone, so the configuration files of
# wpa_supplicant and hostapd have no program that would read them.
#
# They stay in the root filesystem overlay anyway: the packages that
# installed them were part of an earlier build of this tree, and
# Buildroot does not remove files from the overlay when a package is
# switched off. Without this they would keep ending up in the image.

# The first argument is the target directory, the second one is the
# overlay directory that the configuration files are left in.

TARGET_DIR="${1:?the target directory is required}"
OVERLAY="${2:-$TARGET_DIR}"

rm -f "$OVERLAY"/etc/wpa_supplicant.conf
rm -f "$OVERLAY"/etc/wpa_supplicant_s1g.conf
rm -f "$OVERLAY"/etc/hostapd.conf
rm -f "$OVERLAY"/etc/hostapd.conf.default
rm -f "$OVERLAY"/etc/hostapd_2g4.conf
rm -f "$OVERLAY"/etc/hostapd_5g.conf

rm -f "$TARGET_DIR"/etc/wpa_supplicant.conf
rm -f "$TARGET_DIR"/etc/wpa_supplicant_s1g.conf
rm -f "$TARGET_DIR"/etc/hostapd.conf
rm -f "$TARGET_DIR"/etc/hostapd.conf.default
rm -f "$TARGET_DIR"/etc/hostapd_2g4.conf
rm -f "$TARGET_DIR"/etc/hostapd_5g.conf
