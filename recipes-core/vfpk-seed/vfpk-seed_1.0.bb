#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "First-boot unpacker for a seeded flatpak installation"
DESCRIPTION = "vfpk-seed.service unpacks the flatpak installation that \
               flatpak-cross-install seeded at build time \
               (FLATPAK_DEPLOY_MODE = \"seed\") into the writable \
               /var/lib/flatpak on first boot, and never over an existing \
               installation. For user scope, flatpak-cross-install adds \
               vfpk-seed-user.service, which runs it as the configured \
               account to seed its home."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"
SECTION = "base"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://vfpk-seed.sh \
    file://vfpk-seed.service \
"

S = "${UNPACKDIR}"

inherit allarch features_check systemd

REQUIRED_DISTRO_FEATURES = "systemd"

# Must match FLATPAK_SEED in flatpak-cross-install.bbclass.
VFPK_SEED = "${datadir}/vfpk/seed.tar"
VFPK_SEED_DIR = "${localstatedir}/lib/flatpak"

SYSTEMD_SERVICE:${PN} = "vfpk-seed.service"

do_install() {
    install -D -m 0755 ${S}/vfpk-seed.sh ${D}${libexecdir}/vfpk-seed
    install -D -m 0644 ${S}/vfpk-seed.service ${D}${systemd_system_unitdir}/vfpk-seed.service
    sed -i -e 's,@SEED@,${VFPK_SEED},g' -e 's,@DIR@,${VFPK_SEED_DIR},g' \
        -e 's,@LIBEXECDIR@,${libexecdir},g' \
        ${D}${libexecdir}/vfpk-seed ${D}${systemd_system_unitdir}/vfpk-seed.service
}

FILES:${PN} += "${systemd_system_unitdir}/vfpk-seed.service"
