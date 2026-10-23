#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# flutter-engine-<mode>-extension-image packaged for build-time install.

SUMMARY = "Flutter engine extension, ${FLUTTER_ENGINE_EXTENSION_MODE} mode, packaged"
DESCRIPTION = "The org.flatpak_minimal.Flutter.Engine.${FLUTTER_ENGINE_EXTENSION_MODE} \
               extension from ${FLATPAK_IMAGE}, in the form \
               flatpak-cross-install installs at build time."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "BSD-3-Clause"

inherit flatpak-bundle

# Package names cannot have '_': jit_release is flutter-engine-jit-release-extension.
FLATPAK_IMAGE = "flutter-engine-${@d.getVar('FLUTTER_ENGINE_EXTENSION_MODE').replace('_', '-')}-extension-image"

# meta-flutter builds the release engine by default; the other modes only
# with PACKAGECONFIG:pn-flutter-engine, so world leaves them out.
EXCLUDE_FROM_WORLD = "${@'0' if d.getVar('FLUTTER_ENGINE_EXTENSION_MODE') == 'release' else '1'}"
