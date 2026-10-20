#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Minimal flatpak runtime for testing vfpk, packaged"
DESCRIPTION = "The org.flatpak_minimal.Test.Platform runtime from \
               vfpk-test-runtime-image, in the form flatpak-cross-install \
               installs at build time."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

# busybox (GPL-2.0-only) and glibc's dynamic linker (LGPL-2.1-or-later), as
# vfpk-test-runtime-image's license manifest lists them.
LICENSE = "CLOSED"

inherit flatpak-bundle

FLATPAK_IMAGE = "vfpk-test-runtime-image"
