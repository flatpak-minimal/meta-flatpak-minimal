#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Base flatpak SDK"
DESCRIPTION = "org.flatpak_minimal.Sdk: the packages of \
               org.flatpak_minimal.Platform from the same build, plus their \
               development files and a native toolchain, so apps build \
               against the runtime's ABI with flatpak-builder. SDK extensions \
               mount under /usr/lib/sdk."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit features_check flatpak-runtime-image

require flatpak-platform.inc

FLATPAK_RUNTIME_ID = "${FLATPAK_PLATFORM_SDK_ID}"
FLATPAK_RUNTIME_PLATFORM = "${FLATPAK_PLATFORM_ID}"

IMAGE_FEATURES:append = " dev-pkgs"

IMAGE_INSTALL = "\
    ${FLATPAK_PLATFORM_PACKAGES} \
    packagegroup-core-sdk \
    bash \
    cmake \
    coreutils \
    diffutils \
    file \
    findutils \
    gawk \
    grep \
    gzip \
    ninja \
    patch \
    sed \
    tar \
    which \
    xz \
"
