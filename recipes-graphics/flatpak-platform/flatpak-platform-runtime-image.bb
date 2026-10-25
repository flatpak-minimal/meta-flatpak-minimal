#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Base flatpak runtime"
DESCRIPTION = "org.flatpak_minimal.Platform: the Wayland and Mesa stack, \
               fonts and certificates, built by this build and committed as \
               a flatpak runtime. Apps and toolkit extensions built here run \
               on it."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit features_check flatpak-runtime-image

require flatpak-platform.inc

FLATPAK_RUNTIME_ID = "${FLATPAK_PLATFORM_ID}"
FLATPAK_RUNTIME_SDK = "${FLATPAK_PLATFORM_SDK_ID}"

FLATPAK_RUNTIME_PACKAGES = "${FLATPAK_PLATFORM_PACKAGES}"
