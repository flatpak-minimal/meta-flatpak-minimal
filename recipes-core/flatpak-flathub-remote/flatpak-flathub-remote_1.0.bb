#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Pre-seed the Flathub flatpak remote on first boot"
HOMEPAGE = "https://flathub.org"
SECTION = "base"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://flatpak-add-flathub-remote.service \
           file://flatpak-add-flathub-remote-system.service \
           file://flatpak-appstream-refresh.service \
           file://flatpak-appstream-refresh-system.service \
"

S = "${UNPACKDIR}"

inherit allarch systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd polkit"

SYSTEMD_SERVICE:${PN} = " \
    flatpak-add-flathub-remote.service \
    flatpak-add-flathub-remote-system.service \
    flatpak-appstream-refresh.service \
    flatpak-appstream-refresh-system.service \
"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# Account the --user flatpak data is registered under; override on non-AGL
# builds that lack this account (the service then just fails at boot).
FLATPAK_MINIMAL_USER ??= "agl-driver"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/flatpak-add-flathub-remote.service \
        ${S}/flatpak-add-flathub-remote-system.service \
        ${S}/flatpak-appstream-refresh.service \
        ${S}/flatpak-appstream-refresh-system.service \
        ${D}${systemd_system_unitdir}/
    sed -i -e 's,@FLATPAK_MINIMAL_USER@,${FLATPAK_MINIMAL_USER},g' \
        ${D}${systemd_system_unitdir}/flatpak-add-flathub-remote.service \
        ${D}${systemd_system_unitdir}/flatpak-appstream-refresh.service
}

FILES:${PN} += "${systemd_system_unitdir}"

RDEPENDS:${PN} = "flatpak"
