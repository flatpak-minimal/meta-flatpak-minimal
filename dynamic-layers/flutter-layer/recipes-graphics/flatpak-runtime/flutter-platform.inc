#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# What the Flutter runtime and its SDK share: IDs, branch and packages.

require conf/include/flutter-version.inc

REQUIRED_DISTRO_FEATURES = "opengl usrmerge wayland"

FLUTTER_PLATFORM_ID = "org.flatpak_minimal.Flutter.Platform"
FLUTTER_SDK_ID = "org.flatpak_minimal.Flutter.Sdk"

# The Flutter SDK version, so the engine always matches the apps' AOT code.
FLATPAK_RUNTIME_BRANCH = "${@get_flutter_sdk_version(d)}"

# busybox gives app launchers a /bin/sh; flatpak runs ldconfig to build the
# sandbox's linker cache. Mesa's drivers are loaded at runtime, so nothing
# pulls them in through library dependencies.
FLUTTER_PLATFORM_PACKAGES = "\
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
