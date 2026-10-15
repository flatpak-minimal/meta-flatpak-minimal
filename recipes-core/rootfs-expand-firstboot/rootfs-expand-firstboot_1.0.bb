#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Grow the root partition and filesystem to fill the disk on boot"
HOMEPAGE = "https://github.com/flatpak-minimal"
SECTION = "base"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://expand-rootfs.sh \
           file://rootfs-expand.service \
          "

S = "${UNPACKDIR}"

inherit systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd"

SYSTEMD_SERVICE:${PN} = "rootfs-expand.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${S}/expand-rootfs.sh ${D}${sbindir}/expand-rootfs.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/rootfs-expand.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += "${systemd_system_unitdir}/rootfs-expand.service"

RDEPENDS:${PN} = "parted util-linux-lsblk util-linux-findmnt e2fsprogs-resize2fs udev"
