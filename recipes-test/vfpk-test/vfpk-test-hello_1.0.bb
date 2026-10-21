#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Minimal flatpak app for testing vfpk"
DESCRIPTION = "org.flatpak_minimal.Test.Hello: a shell script on the \
               org.flatpak_minimal.Test.Platform runtime that reports the \
               flatpak ID it runs under. Packaged as a flatpak app in \
               vfpk-test-hello-flatpak, for testimage."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://vfpk-test-hello.sh"

S = "${UNPACKDIR}"

inherit flatpak-app

FLATPAK_APP_ID = "org.flatpak_minimal.Test.Hello"
FLATPAK_APP_BRANCH = "1"
FLATPAK_APP_RUNTIME = "org.flatpak_minimal.Test.Platform"
FLATPAK_APP_RUNTIME_BRANCH = "1"
FLATPAK_APP_RUNTIME_PACKAGE = "vfpk-test-runtime"
FLATPAK_APP_FILES = "${datadir}/vfpk-test-hello"
FLATPAK_APP_COMMAND = "sh ${datadir}/vfpk-test-hello/hello"

do_install() {
    install -D -m 0755 ${S}/vfpk-test-hello.sh ${D}${datadir}/vfpk-test-hello/hello
}
