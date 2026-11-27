#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# FLATPAK_OPENPGP chooses what verifies OpenPGP signatures on the target:
#
#   gpgme    GPGME and gpg, as ostree is built by default. GnuPG, which is
#            GPL-3.0-only, is then on the image.
#   sequoia  openpgp-verify-sequoia. Pulls from GPG-signed remotes are
#            verified as before, Flathub among them, and neither GnuPG nor
#            GPGME is installed. Signing and listing keys are not available
#            on the target.
#
# Set it in the distro or local.conf: flatpak_%.bbappend and
# vfpk-rootfs-image read it too. Native and nativesdk ostree keep GPGME:
# they sign.
FLATPAK_OPENPGP ??= "gpgme"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

FLATPAK_OPENPGP_SEQUOIA = "${@'1' if d.getVar('FLATPAK_OPENPGP') == 'sequoia' else ''}"

SRC_URI:append:class-target = "${@' file://0001-Add-a-Sequoia-backend-for-OpenPGP-signature-verifica.patch' if d.getVar('FLATPAK_OPENPGP_SEQUOIA') else ''}"

# No --without-sequoia: unpatched, configure does not know the option.
PACKAGECONFIG[sequoia] = "--with-sequoia,,openpgp-verify-sequoia"
PACKAGECONFIG:remove:class-target = "${@'gpgme' if d.getVar('FLATPAK_OPENPGP_SEQUOIA') else ''}"
PACKAGECONFIG:append:class-target = "${@' sequoia' if d.getVar('FLATPAK_OPENPGP_SEQUOIA') else ''}"

python () {
    if d.getVar('FLATPAK_OPENPGP') not in ('gpgme', 'sequoia'):
        bb.fatal("FLATPAK_OPENPGP must be 'gpgme' or 'sequoia', not '%s'" % d.getVar('FLATPAK_OPENPGP'))
}
