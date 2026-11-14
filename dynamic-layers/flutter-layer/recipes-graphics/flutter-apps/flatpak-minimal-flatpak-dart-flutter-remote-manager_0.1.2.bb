#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
# Copyright (c) 2026 Joel Winarske
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "flutter_remote_manager"
DESCRIPTION = "Flutter Linux desktop app demonstrating the flatpak_dart package."
AUTHOR = "Joel Winarske"
HOMEPAGE = "https://github.com/flatpak-minimal/flatpak_dart"
BUGTRACKER = "https://github.com/flatpak-minimal/flatpak_dart/issues"
SECTION = "graphics"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=2ae04493455a6ed09a6df86162e3cbb4"

SRCREV = "1b31c7ef6ba4b8f29cd26382f9c66a348544c115"
SRC_URI = "git://github.com/flatpak-minimal/flatpak_dart.git;branch=main;protocol=https"

# glz::Reader handed 64-bit wire lengths to containers whose size_type is
# 32-bit, so the native library did not compile for a 32-bit machine. Carried
# as a patch rather than by moving SRCREV: main is at 0.3.0 with new Dart
# dependencies and two more C++ sources, which is a recipe upgrade and not this
# fix. Drop it when this recipe moves to 0.3.0.
SRC_URI += "file://0001-glz-Reader-do-not-narrow-wire-lengths-on-32-bit.patch"

# native/CMakeLists.txt: pkg_check_modules(flatpak, glib-2.0), both REQUIRED.
DEPENDS += "\
    flatpak \
    glib-2.0 \
"

FLUTTER_APPLICATION_PATH = "example/flutter_remote_manager"
PUBSPEC_APPNAME = "flutter_remote_manager"
FLUTTER_APPLICATION_INSTALL_SUFFIX = "flatpak-dart-example-flutter-remote-manager"

# flatpak itself declares REQUIRED_DISTRO_FEATURES = "polkit"; declare it here
# too so this app is skipped with a clear reason on a distro without polkit,
# rather than failing with "Nothing PROVIDES 'flatpak'".
REQUIRED_DISTRO_FEATURES = "polkit"

inherit features_check flutter-app-native

RDEPENDS:${PN} += "flatpak"
