#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# org.flatpak_minimal.Flutter.Engine.<mode> for FLUTTER_ENGINE_EXTENSION_MODE.

SUMMARY = "Flutter engine flatpak extension, ${FLUTTER_ENGINE_EXTENSION_MODE} mode"
DESCRIPTION = "libflutter_engine.so of the ${FLUTTER_ENGINE_EXTENSION_MODE} runtime \
               mode and its ICU data, as an extension of \
               org.flatpak_minimal.Platform. Apps of that mode packaged with \
               flatpak-flutter-app mount it at /app/flutter."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit features_check flatpak-extension-image

require flutter-extension.inc

FLATPAK_EXTENSION_ID = "${@flatpak_flutter_engine_id(d, d.getVar('FLUTTER_ENGINE_EXTENSION_MODE'))}"
FLATPAK_EXTENSION_BRANCH = "${FLATPAK_FLUTTER_ENGINE_BRANCH}"
FLATPAK_EXTENSION_BASE = "flatpak-platform-runtime-image"
FLATPAK_EXTENSION_OF = "runtime/${FLATPAK_PLATFORM_ID}/${FLATPAK_ARCH}/${FLATPAK_PLATFORM_BRANCH}"

IMAGE_INSTALL = "${@flatpak_flutter_engine_package(d, d.getVar('FLUTTER_ENGINE_EXTENSION_MODE'))}"

# A .flatpak per engine, named for its mode and engine version.
FLATPAK_DEPLOY_BUNDLES ?= "1"
