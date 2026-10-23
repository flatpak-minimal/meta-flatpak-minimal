#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# The Flutter engine as flatpak extensions of org.flatpak_minimal.Platform,
# one per runtime mode and engine version:
#
#   org.flatpak_minimal.Flutter.Engine.<mode>//<engine version>-<runtime branch>
#
# with <mode> one of debug, profile, release and jit_release, as meta-flutter
# names them, and <engine version> the Flutter SDK version and the first 12
# digits of the engine commit (3.47.7-deb287481e3c). An app's AOT or kernel
# snapshot only runs on the engine it was built for, so each mode and engine
# installs side by side.
# The commit is what meta-flutter builds flutter-engine from for
# FLUTTER_SDK_TAG; an upstream Flutter SDK of that version names the same
# one in bin/internal/engine.version.
#
# Package names cannot have '_', so meta-flutter's package for jit_release is
# flutter-engine-jit-release, and the extension's is
# flutter-engine-jit-release-extension.
#
# Shared by flatpak-flutter-app and the extension recipes; needs
# meta-flutter's conf/include/flutter-version.inc and gn-utils.inc.

FLATPAK_FLUTTER_ENGINE_MODES = "debug profile release jit_release"
FLATPAK_FLUTTER_ENGINE_VERSION = "${@flatpak_flutter_engine_version(d)}"
FLATPAK_FLUTTER_ENGINE_BRANCH = "${FLATPAK_FLUTTER_ENGINE_VERSION}-${FLATPAK_PLATFORM_BRANCH}"

def flatpak_flutter_engine_version(d):
    """<Flutter SDK version>-<engine commit, 12 digits>."""
    import re
    commit = gn_get_engine_commit(d)
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        bb.fatal("engine commit '%s' for FLUTTER_SDK_TAG %s is not a git commit" % (commit, d.getVar('FLUTTER_SDK_TAG')))
    return '%s-%s' % (get_flutter_sdk_version(d), commit[:12])

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
