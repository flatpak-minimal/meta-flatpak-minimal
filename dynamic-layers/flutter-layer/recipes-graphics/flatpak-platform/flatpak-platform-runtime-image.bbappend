#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# One Flutter embedder per runtime: ivi-homescreen loads libflutter_engine.so
# from the app's bundle, which links into the org.flatpak_minimal.Flutter.Engine
# extension of the app's Flutter version. The engine it depends on goes there,
# not into the runtime.
FLATPAK_PLATFORM_PACKAGES:append = " ivi-homescreen"
FLATPAK_RUNTIME_EXCLUDE_RECIPES:append = " flutter-engine"
