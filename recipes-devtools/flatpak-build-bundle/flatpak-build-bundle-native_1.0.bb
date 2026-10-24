#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Write single-file flatpak bundles with libostree"
DESCRIPTION = "flatpak-build-bundle writes the .flatpak file 'flatpak \
               build-bundle' does for a ref in an ostree repository, without \
               a native flatpak. flatpak-deploy uses it for \
               FLATPAK_DEPLOY_BUNDLES."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"
SECTION = "devel"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "glib-2.0-native ostree-native"

SRC_URI = "file://flatpak-build-bundle.c"

S = "${UNPACKDIR}"

inherit pkgconfig native

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} -Wall -Werror -o flatpak-build-bundle ${S}/flatpak-build-bundle.c \
        $(pkg-config --cflags --libs ostree-1 gio-2.0)
}

do_install() {
    install -D -m 0755 flatpak-build-bundle ${D}${bindir}/flatpak-build-bundle
}
