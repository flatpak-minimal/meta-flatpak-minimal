#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# The Flutter engine as flatpak extensions of org.flatpak_minimal.Platform,
# one per runtime mode:
#
#   org.flatpak_minimal.Flutter.Engine.<mode>//<flutter version>-<runtime branch>
#
# with <mode> one of debug, profile, release and jit_release, as meta-flutter
# names them. An app's AOT or kernel snapshot only runs on the engine of its
# own mode and Flutter version.
#
# Package names cannot have '_', so meta-flutter's package for jit_release is
# flutter-engine-jit-release, and the extension's is
# flutter-engine-jit-release-extension.
#
# Shared by flatpak-flutter-app and the extension recipes; needs
# meta-flutter's conf/include/flutter-version.inc.

FLATPAK_FLUTTER_ENGINE_MODES = "debug profile release jit_release"
FLATPAK_FLUTTER_ENGINE_BRANCH = "${@get_flutter_sdk_version(d)}-${FLATPAK_PLATFORM_BRANCH}"

def flatpak_flutter_engine_mode(d, mode):
    """The runtime mode, checked against FLATPAK_FLUTTER_ENGINE_MODES."""
    if mode not in (d.getVar('FLATPAK_FLUTTER_ENGINE_MODES') or '').split():
        bb.fatal("'%s' is not a Flutter engine runtime mode (%s)"
                 % (mode, ', '.join(d.getVar('FLATPAK_FLUTTER_ENGINE_MODES').split())))
    return mode

def flatpak_flutter_engine_dir(d, mode):
    """Directory of the mode under ${datadir}/flutter/<version>/."""
    return flatpak_flutter_engine_mode(d, mode)

def flatpak_flutter_engine_package(d, mode):
    """meta-flutter's package with the mode's engine."""
    return 'flutter-engine-' + flatpak_flutter_engine_mode(d, mode).replace('_', '-')

def flatpak_flutter_engine_id(d, mode):
    return 'org.flatpak_minimal.Flutter.Engine.' + flatpak_flutter_engine_mode(d, mode)

def flatpak_flutter_engine_extension_package(d, mode):
    """The flatpak-bundle package carrying the mode's extension."""
    return 'flutter-engine-%s-extension' % flatpak_flutter_engine_mode(d, mode).replace('_', '-')
