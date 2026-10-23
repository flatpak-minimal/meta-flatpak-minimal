#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# flatpak-app defaults for a meta-flutter app recipe (flutter-app or
# flutter-app-native): the app ref holds only the app's bundle and runs on the
# layer's base runtime (flatpak-platform-runtime-image) with its embedder,
# ivi-homescreen. The engine comes from the extension of the app's runtime
# mode, org.flatpak_minimal.Flutter.Engine.<mode> (flatpak-flutter-engine),
# whose branch is the Flutter SDK version and the runtime's branch, so the
# engine matches the app's snapshot; apps on different Flutter versions and
# modes share the runtime.
#
#   inherit flutter-app-native flatpak-flutter-app
#   FLATPAK_APP_ID = "org.example.App"
#
# The extension is mounted at /app/${FLATPAK_FLUTTER_ENGINE_DIR}. The
# bundle's links to libflutter_engine.so and icudtl.dat, which point into
# ${datadir}/flutter/<version>, are pointed there.

# Before inherit flatpak-app: its anonymous function checks the extension
# flags set here, and anonymous functions run in parse order.
python () {
    if not d.getVar('FLUTTER_INSTALL_DIR'):
        bb.fatal("flatpak-flutter-app needs a meta-flutter app recipe (inherit flutter-app or flutter-app-native first)")
    mode = d.getVar('FLATPAK_FLUTTER_RUNTIME_MODE')
    if mode not in (d.getVar('FLUTTER_APP_RUNTIME_MODES') or '').split():
        bb.fatal("FLATPAK_FLUTTER_RUNTIME_MODE '%s' is not in FLUTTER_APP_RUNTIME_MODES '%s'"
                 % (mode, d.getVar('FLUTTER_APP_RUNTIME_MODES')))
    engine = flatpak_flutter_engine_id(d, mode)
    d.appendVar('FLATPAK_APP_EXTENSIONS', ' ' + engine)
    d.setVarFlag('FLATPAK_APP_EXTENSION_VERSION', engine, '%s-${FLATPAK_APP_RUNTIME_BRANCH}' % get_flutter_sdk_version(d))
    d.setVarFlag('FLATPAK_APP_EXTENSION_DIRECTORY', engine, '${FLATPAK_FLUTTER_ENGINE_DIR}')
    d.setVarFlag('FLATPAK_APP_EXTENSION_PACKAGE', engine, flatpak_flutter_engine_extension_package(d, mode))
    d.setVarFlag('FLATPAK_APP_EXTENSION_PATHS', engine, '${datadir}/flutter/%s' % get_flutter_sdk_version(d))
}

inherit flatpak-app flatpak-flutter-engine

FLATPAK_FLUTTER_RUNTIME_MODE ??= "release"
FLATPAK_FLUTTER_BUNDLE = "${FLUTTER_INSTALL_DIR}/${@get_flutter_sdk_version(d)}/${FLATPAK_FLUTTER_RUNTIME_MODE}"
FLATPAK_FLUTTER_ENGINE_DIR = "flutter"
FLATPAK_FLUTTER_EMBEDDER ??= "homescreen"

FLATPAK_APP_FILES ??= "${FLATPAK_FLUTTER_BUNDLE}"
FLATPAK_APP_COMMAND ??= "${FLATPAK_FLUTTER_EMBEDDER} -b ${FLATPAK_FLUTTER_BUNDLE}"
# flutter-app-native installs native-assets libraries here; dlopen finds them
# by name through the linker search path.
FLATPAK_APP_LIBDIRS ??= "${FLATPAK_FLUTTER_BUNDLE}/lib/native_assets"
# App recipes put libraries Dart opens by bare name (dlopen("libsqlite3.so"))
# beside libapp.so; in the sandbox that directory belongs to the app alone.
FLATPAK_APP_LD_LIBRARY_PATH ??= "${FLATPAK_FLUTTER_BUNDLE}/lib"
FLATPAK_APP_RUNTIME ??= "${FLATPAK_PLATFORM_ID}"
FLATPAK_APP_RUNTIME_BRANCH ??= "${FLATPAK_PLATFORM_BRANCH}"
FLATPAK_APP_RUNTIME_PACKAGE ??= "${FLATPAK_PLATFORM_PACKAGE}"
FLATPAK_APP_FINISH_ARGS ??= "--socket=wayland --device=dri --share=ipc"
