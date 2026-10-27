#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "First-boot growth of the flatpak data partition"
DESCRIPTION = "vfpk-growpart extends the flatpak data partition that \
               flatpak-cross-install builds (FLATPAK_DEPLOY_MODE = \
               \"partition\") to the end of its disk, so apps get the rest \
               of the device. The class generates the unit that runs it \
               before the partition is mounted; systemd-growfs then grows \
               the filesystem."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"
SECTION = "base"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://vfpk-growpart.sh"

S = "${UNPACKDIR}"

inherit allarch

do_install() {
    install -D -m 0755 ${S}/vfpk-growpart.sh ${D}${libexecdir}/vfpk-growpart
}

RDEPENDS:${PN} = "util-linux-sfdisk util-linux-resizepart"
