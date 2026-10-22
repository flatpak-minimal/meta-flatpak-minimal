#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Flutter flatpak SDK"
DESCRIPTION = "org.flatpak_minimal.Flutter.Sdk: the packages of \
               org.flatpak_minimal.Flutter.Platform from the same build, plus \
               their development files, a native toolchain and the Flutter \
               engine's headers and SDK files, so native code (FFI libraries, \
               plugins, embedders) builds against the runtime's ABI with \
               flatpak-builder. Dart AOT is not in it: meta-flutter builds \
               gen_snapshot only for the build machine."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit features_check flatpak-runtime-image

require flutter-platform.inc

FLATPAK_RUNTIME_ID = "${FLUTTER_SDK_ID}"
FLATPAK_RUNTIME_PLATFORM = "${FLUTTER_PLATFORM_ID}"

# The -dev package of everything installed.
IMAGE_FEATURES:append = " dev-pkgs"

# packagegroup-core-sdk is core-image's tools-sdk: compiler, binutils,
# make, pkg-config and friends. The rest is what flatpak-builder's build
# systems and a typical build script expect.
IMAGE_INSTALL = "\
    ${FLUTTER_PLATFORM_PACKAGES} \
    packagegroup-core-sdk \
    bash \
    cmake \
    coreutils \
    diffutils \
    file \
    findutils \
    flutter-engine-dev \
    flutter-engine-sdk-dev \
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
