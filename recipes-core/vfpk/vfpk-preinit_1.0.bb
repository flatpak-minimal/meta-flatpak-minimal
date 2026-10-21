#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Preinit for the vfpk guest initramfs"
DESCRIPTION = "/init of the vfpk tiny initramfs: mounts the squashfs root \
               filesystem under a tmpfs overlay and switches to it."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"
SECTION = "base"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

SRC_URI = "file://vfpk-preinit.sh"

S = "${UNPACKDIR}"

do_install() {
    install -D -m 0755 ${S}/vfpk-preinit.sh ${D}/init
}

FILES:${PN} += "/init"

RDEPENDS:${PN} = "busybox"
