#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Minimal flatpak runtime for testing vfpk"
DESCRIPTION = "org.flatpak_minimal.Test.Platform: busybox and the dynamic \
               linker, committed as a flatpak runtime. Small enough to build \
               and install on every architecture vfpk supports, for testimage."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit flatpak-runtime-image

FLATPAK_RUNTIME_ID = "org.flatpak_minimal.Test.Platform"
FLATPAK_RUNTIME_BRANCH = "1"

FLATPAK_RUNTIME_PACKAGES = "busybox ldconfig"
