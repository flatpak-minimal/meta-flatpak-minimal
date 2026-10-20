#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Host runner for the vfpk guest"
DESCRIPTION = "vfpk-runner.sh boots the vfpk QEMU guest of the target \
               architecture, runs one command in it and collects the flatpak \
               installation it leaves behind."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"
SECTION = "devel"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

SRC_URI = "file://vfpk-runner.sh"

S = "${UNPACKDIR}"

inherit native

do_install() {
    install -D -m 0755 ${S}/vfpk-runner.sh ${D}${bindir}/vfpk-runner.sh
}

# Native RDEPENDS land in the sysroot of whatever depends on vfpk-native.
RDEPENDS:${PN} = "e2fsprogs-native qemu-system-native"
