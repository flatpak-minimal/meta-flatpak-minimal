#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "ivi-homescreen flatpak extension, packaged"
DESCRIPTION = "The org.flatpak_minimal.Flutter.Homescreen extension from \
               flutter-homescreen-extension-image, in the form \
               flatpak-cross-install installs at build time."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "Apache-2.0 & ${@flatpak_license_name(d, 'Apache-2.0-with-LLVM-exception')}"

inherit flatpak-bundle

FLATPAK_IMAGE = "flutter-homescreen-extension-image"
