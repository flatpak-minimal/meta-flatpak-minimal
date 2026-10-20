#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Flutter flatpak runtime"
DESCRIPTION = "org.flatpak_minimal.Flutter.Platform: the Flutter engine, \
               ivi-homescreen and the Wayland and Mesa stack, built by this \
               build and committed as a flatpak runtime. Flutter apps packaged \
               with flatpak-flutter-app run on it. The branch is the Flutter \
               SDK version, so the engine always matches the apps' AOT code."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit features_check flatpak-runtime-image

require conf/include/flutter-version.inc

REQUIRED_DISTRO_FEATURES = "opengl usrmerge wayland"

FLATPAK_RUNTIME_ID = "org.flatpak_minimal.Flutter.Platform"
FLATPAK_RUNTIME_BRANCH = "${@get_flutter_sdk_version(d)}"

# busybox gives app launchers a /bin/sh; flatpak runs ldconfig to build the
# sandbox's linker cache. Mesa's drivers are loaded at runtime, so nothing
# pulls them in through library dependencies.
IMAGE_INSTALL = "\
    busybox \
    ca-certificates \
    fontconfig \
    ivi-homescreen \
    ${FLUTTER_ENGINE_PACKAGE} \
    ldconfig \
    libsqlite3 \
    mesa-megadriver \
    ttf-bitstream-vera \
    xkeyboard-config \
"
