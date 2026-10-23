#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Flutter engine flatpak extension"
DESCRIPTION = "org.flatpak_minimal.Flutter.Engine: libflutter_engine.so and \
               its ICU data, as an extension of org.flatpak_minimal.Platform. \
               Apps packaged with flatpak-flutter-app mount it at /app/flutter \
               and run with the runtime's ivi-homescreen. The branch is the \
               Flutter SDK version and the runtime's branch, so apps on \
               different Flutter versions share one runtime."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit features_check flatpak-extension-image

require flutter-extension.inc

FLATPAK_EXTENSION_ID = "org.flatpak_minimal.Flutter.Engine"
FLATPAK_EXTENSION_BRANCH = "${FLUTTER_ENGINE_EXTENSION_BRANCH}"
FLATPAK_EXTENSION_BASE = "flatpak-platform-runtime-image"
FLATPAK_EXTENSION_OF = "runtime/${FLATPAK_PLATFORM_ID}/${FLATPAK_ARCH}/${FLATPAK_PLATFORM_BRANCH}"

IMAGE_INSTALL = "${FLUTTER_ENGINE_PACKAGE}"
