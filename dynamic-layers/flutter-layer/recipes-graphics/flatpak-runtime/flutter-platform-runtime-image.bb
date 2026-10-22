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

require flutter-platform.inc

FLATPAK_RUNTIME_ID = "${FLUTTER_PLATFORM_ID}"
FLATPAK_RUNTIME_SDK = "${FLUTTER_SDK_ID}"

IMAGE_INSTALL = "${FLUTTER_PLATFORM_PACKAGES}"
