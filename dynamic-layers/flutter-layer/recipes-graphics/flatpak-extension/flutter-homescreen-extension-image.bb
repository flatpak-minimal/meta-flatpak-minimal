#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "ivi-homescreen flatpak extension"
DESCRIPTION = "org.flatpak_minimal.Flutter.Homescreen: the ivi-homescreen \
               Flutter embedder, as an extension of org.flatpak_minimal.Platform. \
               Apps packaged with flatpak-flutter-app mount it at \
               /app/homescreen. It loads libflutter_engine.so from the app's \
               bundle and is independent of the engine's runtime mode and \
               version."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit features_check flatpak-extension-image flatpak-flutter-homescreen

REQUIRED_DISTRO_FEATURES = "opengl usrmerge wayland"

FLATPAK_EXTENSION_ID = "${FLATPAK_FLUTTER_HOMESCREEN_ID}"
FLATPAK_EXTENSION_BRANCH = "${FLATPAK_FLUTTER_HOMESCREEN_BRANCH}"
FLATPAK_EXTENSION_BASE = "flatpak-platform-runtime-image"
FLATPAK_EXTENSION_OF = "runtime/${FLATPAK_PLATFORM_ID}/${FLATPAK_ARCH}/${FLATPAK_PLATFORM_BRANCH}"

# RPM scriptlets require /bin/sh. Select the base runtime's BusyBox
# explicitly so the solver does not add Bash and base-files to the extension.
FLATPAK_EXTENSION_PACKAGES = "busybox ivi-homescreen"
# meta-flutter's ivi-homescreen RDEPENDS on flutter-engine, every built
# mode; the app's engine comes from its Engine.<mode> extension.
FLATPAK_EXTENSION_EXCLUDE_RECIPES = "flutter-engine"
