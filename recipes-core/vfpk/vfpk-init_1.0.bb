#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Init of the vfpk guest"
DESCRIPTION = "PID 1 of the vfpk guest: runs the command vfpk-runner.sh \
               hands over, writes the results to the result disks and \
               powers off."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"
SECTION = "base"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

SRC_URI = "file://vfpk-init.sh"

S = "${UNPACKDIR}"

do_install() {
    install -D -m 0755 ${S}/vfpk-init.sh ${D}${base_sbindir}/vfpk-init
}

# GNU tar: busybox tar cannot report the archive size the runner needs.
RDEPENDS:${PN} = "busybox tar"
