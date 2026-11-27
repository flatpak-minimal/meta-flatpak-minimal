#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# In the vfpk guest flatpak runs as root under a single init script, with no
# D-Bus and no polkit: as uid 0 it never calls the system helper. Build it
# without the helper so the guest does not need polkit. Scoped to the vfpk
# distro, so other builds are unaffected.
REQUIRED_DISTRO_FEATURES:remove:vfpk = "polkit"
DEPENDS:remove:vfpk = "polkit"
EXTRA_OEMESON:append:vfpk = " -Dsystem_helper=disabled"

# FLATPAK_OPENPGP = "sequoia" (see ostree_%.bbappend): flatpak itself calls
# GPGME in one place, for the signatures of OCI remotes. Do that with
# openpgp-verify-sequoia too, so that the target needs no GPGME either.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

FLATPAK_OPENPGP_SEQUOIA = "${@'1' if d.getVar('FLATPAK_OPENPGP') == 'sequoia' else ''}"

SRC_URI:append:class-target = "${@' file://0001-Verify-the-signatures-of-OCI-remotes-with-Sequoia-on.patch' if d.getVar('FLATPAK_OPENPGP_SEQUOIA') else ''}"
DEPENDS:remove:class-target = "${@'gpgme' if d.getVar('FLATPAK_OPENPGP_SEQUOIA') else ''}"
DEPENDS:append:class-target = "${@' openpgp-verify-sequoia' if d.getVar('FLATPAK_OPENPGP_SEQUOIA') else ''}"
EXTRA_OEMESON:append:class-target = "${@' -Dsequoia=enabled' if d.getVar('FLATPAK_OPENPGP_SEQUOIA') else ''}"
