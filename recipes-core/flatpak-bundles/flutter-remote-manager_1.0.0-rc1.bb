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
BUNDLE_NAME = "org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager_stable_aarch64.flatpak"

# The release asset name does not change between releases; the download is
# stored under a versioned name so DL_DIR keeps them apart.
SRC_URI = "https://github.com/flatpak-minimal/org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager/releases/download/${BUNDLE_RELEASE}/${BUNDLE_NAME};downloadfilename=${BUNDLE_RELEASE}-${BUNDLE_NAME}"
FLATPAK_BUNDLE_FILE = "${BUNDLE_RELEASE}-${BUNDLE_NAME}"
SRC_URI[sha256sum] = "fc90ffc4c404edfb7521b67a6d0192b708f88aabfa1d858576a250d23edc045d"

FLATPAK_BUNDLE_REF = "app/org.flatpak_minimal.flatpak_dart.example.flutter_remote_manager/aarch64/stable"

# The release bundle is built without 'flatpak build-bundle --repo-url', so
# it carries no remote: it installs and runs, but flatpak cannot update it in
# the field. Rebuild the release with --repo-url to drop this.
FLATPAK_BUNDLE_ALLOW_NO_ORIGIN = "1"

# The released bundle is aarch64 only.
COMPATIBLE_HOST = "aarch64.*-linux"

RDEPENDS:${PN} = "flathub-freedesktop-platform"
# The app is MIT, but it runs only on that runtime, which is restricted;
# without the same flag world builds would fail on a missing runtime.
LICENSE_FLAGS = "flathub"
