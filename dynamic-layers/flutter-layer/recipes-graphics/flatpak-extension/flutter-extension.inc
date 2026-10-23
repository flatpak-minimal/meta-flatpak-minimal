#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Flutter as extensions of the base runtime and SDK. The runtime carries the
# one embedder, ivi-homescreen (flatpak-platform-*.bbappend); the extensions
# carry the engine of one Flutter SDK version, built in the configuration
# that builds the runtime, so it matches the runtime's libraries and the
# apps' AOT code.

require conf/include/flutter-version.inc

REQUIRED_DISTRO_FEATURES = "opengl usrmerge wayland"

FLUTTER_EXTENSION_VERSION = "${@get_flutter_sdk_version(d)}"
# The engine extension's branch: one per Flutter version and runtime branch.
FLUTTER_ENGINE_EXTENSION_BRANCH = "${FLUTTER_EXTENSION_VERSION}-${FLATPAK_PLATFORM_BRANCH}"
# release, profile or debug: the engine build FLUTTER_ENGINE_PACKAGE ships.
FLUTTER_EXTENSION_ENGINE_MODE = "${@d.getVar('FLUTTER_ENGINE_PACKAGE').replace('flutter-engine-', '')}"
