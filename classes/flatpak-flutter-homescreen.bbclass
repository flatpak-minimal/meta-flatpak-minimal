#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# The ivi-homescreen embedder as a flatpak extension of
# org.flatpak_minimal.Platform:
#
#   org.flatpak_minimal.Flutter.Homescreen//<runtime branch>
#
# homescreen is independent of the Flutter engine: it loads
# libflutter_engine.so from the app's bundle through the embedder API and
# has no runtime mode or engine version of its own. Only the app has a
# runtime mode, and it picks the engine (flatpak-flutter-engine). Apps mount
# the extension at /app/${FLATPAK_FLUTTER_HOMESCREEN_DIR}.
#
# Shared by flatpak-flutter-app and the extension recipe.

FLATPAK_FLUTTER_HOMESCREEN_ID = "org.flatpak_minimal.Flutter.Homescreen"
FLATPAK_FLUTTER_HOMESCREEN_BRANCH = "${FLATPAK_PLATFORM_BRANCH}"
FLATPAK_FLUTTER_HOMESCREEN_PACKAGE = "flutter-homescreen-extension"
FLATPAK_FLUTTER_HOMESCREEN_DIR = "homescreen"
