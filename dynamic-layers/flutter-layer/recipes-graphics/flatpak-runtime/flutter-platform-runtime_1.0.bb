#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Flutter flatpak runtime, packaged for build-time install"
DESCRIPTION = "The org.flatpak_minimal.Flutter.Platform runtime from \
               flutter-platform-runtime-image, in the form \
               flatpak-cross-install installs at build time."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

# The runtime aggregates the image's packages under their own licenses; the
# image's license manifest lists them.
LICENSE = "CLOSED"

inherit flatpak-bundle

FLATPAK_IMAGE = "flutter-platform-runtime-image"
