#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# The Flutter engine as extensions of the base runtime and SDK: the engine of
# each runtime mode, and the SDK files, built in the configuration that
# builds the runtime, so they match the runtime's libraries and the apps'
# snapshots.

require conf/include/flutter-version.inc
require conf/include/gn-utils.inc

inherit flatpak-flutter-engine

REQUIRED_DISTRO_FEATURES = "opengl usrmerge wayland"

FLUTTER_EXTENSION_VERSION = "${@get_flutter_sdk_version(d)}"
