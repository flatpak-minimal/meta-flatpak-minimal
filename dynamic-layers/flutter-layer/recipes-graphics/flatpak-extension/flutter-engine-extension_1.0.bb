#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Flutter engine flatpak extension, packaged for build-time install"
DESCRIPTION = "The org.flatpak_minimal.Flutter.Engine extension from \
               flutter-engine-extension-image, in the form \
               flatpak-cross-install installs at build time."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "BSD-3-Clause"

inherit flatpak-bundle

FLATPAK_IMAGE = "flutter-engine-extension-image"
