#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Install the flutter_remote_manager flatpak bundle on boot"
HOMEPAGE = "https://github.com/flatpak-minimal/flatpak_dart"
SECTION = "base"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

BUNDLE_RELEASE = "v1.0.0-rc1"
BUNDLE_FILE = "org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager_stable_aarch64.flatpak"

SRC_URI = "https://github.com/flatpak-minimal/org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager/releases/download/${BUNDLE_RELEASE}/${BUNDLE_FILE};downloadfilename=${BUNDLE_RELEASE}-${BUNDLE_FILE} \
           file://install-remote-manager.sh \
           file://flatpak-install-remote-manager.service \
          "
SRC_URI[sha256sum] = "fc90ffc4c404edfb7521b67a6d0192b708f88aabfa1d858576a250d23edc045d"

S = "${UNPACKDIR}"

inherit systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd polkit"

# The released bundle is aarch64-only; skip cleanly rather than install a
# binary the target can't run.
COMPATIBLE_HOST = "aarch64.*"

SYSTEMD_SERVICE:${PN} = "flatpak-install-remote-manager.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

BUNDLE_DIR = "${datadir}/flatpak-minimal/bundles"

# Account the --user flatpak data is registered under; override on non-AGL
# builds that lack this account (the service then just fails at boot).
FLATPAK_MINIMAL_USER ??= "agl-driver"

do_install() {
    install -d ${D}${BUNDLE_DIR}
    install -m 0644 ${S}/${BUNDLE_RELEASE}-${BUNDLE_FILE} ${D}${BUNDLE_DIR}/${BUNDLE_FILE}

    install -d ${D}${sbindir}
    install -m 0755 ${S}/install-remote-manager.sh ${D}${sbindir}/install-remote-manager.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/flatpak-install-remote-manager.service \
        ${D}${systemd_system_unitdir}/
    sed -i -e 's,@FLATPAK_MINIMAL_USER@,${FLATPAK_MINIMAL_USER},g' \
        ${D}${systemd_system_unitdir}/flatpak-install-remote-manager.service
}

FILES:${PN} += "${BUNDLE_DIR}/${BUNDLE_FILE} \
                ${systemd_system_unitdir}/flatpak-install-remote-manager.service \
               "

RDEPENDS:${PN} = "flatpak flatpak-flathub-remote rootfs-expand-firstboot"
