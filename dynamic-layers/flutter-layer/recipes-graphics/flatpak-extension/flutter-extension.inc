#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Flutter as extensions of the base runtime and SDK. The runtime carries the
# one embedder, ivi-homescreen (flatpak-platform-*.bbappend); the extensions
# carry the engine of one Flutter SDK version, built in the configuration
# that builds the runtime, so it matches the runtime's libraries and the
# apps' snapshots.

require conf/include/flutter-version.inc

inherit flatpak-flutter-engine

REQUIRED_DISTRO_FEATURES = "opengl usrmerge wayland"

FLUTTER_EXTENSION_VERSION = "${@get_flutter_sdk_version(d)}"
