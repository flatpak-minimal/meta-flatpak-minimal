#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Flutter flatpak SDK extension"
DESCRIPTION = "org.flatpak_minimal.Sdk.Extension.flutter<engine version>: the Flutter \
               engine of FLUTTER_SDK_EXTENSION_MODES with its headers and SDK \
               files, and ivi-homescreen's plugin headers and library, for \
               building native code (FFI libraries, plugins, \
               embedders) in org.flatpak_minimal.Sdk with flatpak-builder. \
               Dart AOT is not in it: meta-flutter builds gen_snapshot only \
               for the build machine."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit features_check flatpak-extension-image

require flutter-extension.inc

# Runtime modes to carry, from debug, profile, release and jit_release;
# meta-flutter must build each (PACKAGECONFIG:pn-flutter-engine).
FLUTTER_SDK_EXTENSION_MODES ??= "release"

# An SDK extension's branch is the SDK's, so the engine version goes in the
# ID, and engines install side by side:
# org.flatpak_minimal.Sdk.Extension.flutter3_47_7_deb287481e3c.
FLUTTER_SDK_EXTENSION_NAME = "flutter${@d.getVar('FLATPAK_FLUTTER_ENGINE_VERSION').replace('.', '_').replace('-', '_')}"

FLATPAK_EXTENSION_ID = "${FLATPAK_PLATFORM_SDK_ID}.Extension.${FLUTTER_SDK_EXTENSION_NAME}"
FLATPAK_EXTENSION_BRANCH = "${FLATPAK_PLATFORM_BRANCH}"
FLATPAK_EXTENSION_BASE = "flatpak-platform-sdk-image"
FLATPAK_EXTENSION_OF = "runtime/${FLATPAK_PLATFORM_SDK_ID}/${FLATPAK_ARCH}/${FLATPAK_PLATFORM_BRANCH}"
FLATPAK_EXTENSION_MOUNT = "${libdir}/sdk/${FLUTTER_SDK_EXTENSION_NAME}"
# FLUTTER_ENGINE_RELEASE and so on: each mode's engine directory.
FLATPAK_EXTENSION_ENABLE_VARS = "${@' '.join('FLUTTER_ENGINE_%s=share/flutter/%s/%s' % (flatpak_flutter_engine_mode(d, m).upper(), d.getVar('FLUTTER_EXTENSION_VERSION'), flatpak_flutter_engine_dir(d, m)) for m in d.getVar('FLUTTER_SDK_EXTENSION_MODES').split())}"

IMAGE_INSTALL = "\
    ${@' '.join(flatpak_flutter_engine_package(d, m) for m in d.getVar('FLUTTER_SDK_EXTENSION_MODES').split())} \
    flutter-engine-dev \
    flutter-engine-sdk-dev \
    ivi-homescreen-shared-dev \
"
