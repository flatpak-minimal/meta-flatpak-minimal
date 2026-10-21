#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "flutter_remote_manager flatpak bundle, for build-time install"
DESCRIPTION = "The released flutter_remote_manager .flatpak bundle, \
               installed into the image's system installation at build time \
               by flatpak-cross-install."
HOMEPAGE = "https://github.com/flatpak-minimal/flatpak_dart"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit flatpak-bundle

BUNDLE_RELEASE = "v${PV}"
BUNDLE_NAME = "org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager_stable_${FLATPAK_ARCH}.flatpak"

# The release asset name does not change between releases; the download is
# stored under a versioned name so DL_DIR keeps them apart.
SRC_URI = "https://github.com/flatpak-minimal/org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager/releases/download/${BUNDLE_RELEASE}/${BUNDLE_NAME};downloadfilename=${BUNDLE_RELEASE}-${BUNDLE_NAME};name=${FLATPAK_ARCH}"
FLATPAK_BUNDLE_FILE = "${BUNDLE_RELEASE}-${BUNDLE_NAME}"
SRC_URI[aarch64.sha256sum] = "fc90ffc4c404edfb7521b67a6d0192b708f88aabfa1d858576a250d23edc045d"
SRC_URI[x86_64.sha256sum] = "3837873dba1ec00451e5c5cdf69442b3d276f781ab6e4c52487295a7d6dbeaba"

FLATPAK_BUNDLE_REF = "app/org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager/${FLATPAK_ARCH}/stable"

# The release bundle is built without 'flatpak build-bundle --repo-url', so
# it carries no remote: it installs and runs, but flatpak cannot update it in
# the field. Rebuild the release with --repo-url to drop this.
FLATPAK_BUNDLE_ALLOW_NO_ORIGIN = "1"

# The release ships aarch64 and x86_64 bundles.
COMPATIBLE_HOST = "(aarch64|x86_64).*-linux"

RDEPENDS:${PN} = "flathub-freedesktop-platform"
# The app is MIT, but it runs only on that runtime, which is restricted;
# without the same flag world builds would fail on a missing runtime.
LICENSE_FLAGS = "flathub"
