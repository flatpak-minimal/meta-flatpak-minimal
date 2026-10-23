#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Flutter flatpak SDK extension"
DESCRIPTION = "org.flatpak_minimal.Sdk.Extension.flutter<version>: the Flutter \
               engine with its headers and SDK files, for building native code (FFI libraries, plugins, \
               embedders) in org.flatpak_minimal.Sdk with flatpak-builder. \
               Dart AOT is not in it: meta-flutter builds gen_snapshot only \
               for the build machine."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit features_check flatpak-extension-image

require flutter-extension.inc

# An SDK extension's branch is the SDK's, so the Flutter version goes in the
# ID: org.flatpak_minimal.Sdk.Extension.flutter3_47_7.
FLUTTER_SDK_EXTENSION_NAME = "flutter${@d.getVar('FLUTTER_EXTENSION_VERSION').replace('.', '_')}"

FLATPAK_EXTENSION_ID = "${FLATPAK_PLATFORM_SDK_ID}.Extension.${FLUTTER_SDK_EXTENSION_NAME}"
FLATPAK_EXTENSION_BRANCH = "${FLATPAK_PLATFORM_BRANCH}"
FLATPAK_EXTENSION_BASE = "flatpak-platform-sdk-image"
FLATPAK_EXTENSION_OF = "runtime/${FLATPAK_PLATFORM_SDK_ID}/${FLATPAK_ARCH}/${FLATPAK_PLATFORM_BRANCH}"
FLATPAK_EXTENSION_MOUNT = "${libdir}/sdk/${FLUTTER_SDK_EXTENSION_NAME}"
FLATPAK_EXTENSION_ENABLE_VARS = "FLUTTER_ENGINE=share/flutter/${FLUTTER_EXTENSION_VERSION}/${FLUTTER_EXTENSION_ENGINE_MODE}"

IMAGE_INSTALL = "\
    ${FLUTTER_ENGINE_PACKAGE} \
    flutter-engine-dev \
    flutter-engine-sdk-dev \
"
