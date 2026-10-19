#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Predefined system flatpak remotes"
DESCRIPTION = "Static /etc/flatpak/remotes.d entries, so the system \
               installation has its remotes on first boot without a network \
               or a oneshot unit."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"
SECTION = "base"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit allarch features_check

# flatpak itself requires polkit; skip with that reason rather than fail on a
# missing runtime provider.
REQUIRED_DISTRO_FEATURES = "polkit"

# One entry per remote name. Each remote takes these varflags:
#   FLATPAK_REMOTE_URL[name]           repository URL (required)
#   FLATPAK_REMOTE_TITLE[name]         human-readable title
#   FLATPAK_REMOTE_GPGKEY[name]        file in this recipe's search path
#                                      holding the binary (not ASCII armored)
#                                      public key; 'gpg --export KEYID'
#   FLATPAK_REMOTE_COLLECTION_ID[name] collection ID (requires a GPG key)
#   FLATPAK_REMOTE_FILTER[name]        file in this recipe's search path with
#                                      a flatpak filter for the remote
#   FLATPAK_REMOTE_NO_GPG[name]        "1" to ship a remote with no GPG key.
#                                      flatpak then does not verify anything
#                                      it pulls from it; avoid outside tests.
#
# flatpak applies a remotes.d file once, the first time it opens the system
# repository and only if no remote of that name exists yet. Installations
# seeded at build time already carry the remote, so they keep its origin.
FLATPAK_REMOTES ?= "flathub"

FLATPAK_REMOTE_URL[flathub] ?= "https://dl.flathub.org/repo/"
FLATPAK_REMOTE_TITLE[flathub] ?= "Flathub"
# Exported from https://dl.flathub.org/repo/flathub.flatpakrepo; fingerprint
# 6E5C05D979C76DAF93C081354184DD4D907A7CAE, expires 2027-06-14.
FLATPAK_REMOTE_GPGKEY[flathub] ?= "flathub.gpg"

# The key and filter files are added to SRC_URI from the varflags below.
SRC_URI = ""

S = "${UNPACKDIR}"

python () {
    import re

    remotes = (d.getVar('FLATPAK_REMOTES') or '').split()
    if not remotes:
        raise bb.parse.SkipRecipe('FLATPAK_REMOTES is empty')

    for name in remotes:
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name):
            bb.fatal("flatpak remote name '%s' is not valid" % name)
        for var in (d.getVar('FLATPAK_REMOTE_VARS') or '').split():
            value = d.getVarFlag(var, name) or ''
            # Each value becomes one line of a keyfile; a line break would
            # smuggle in keys the recipe never checked.
            if '\n' in value or '\r' in value:
                bb.fatal("%s[%s] contains a line break" % (var, name))
        for var in ('FLATPAK_REMOTE_GPGKEY', 'FLATPAK_REMOTE_FILTER'):
            value = d.getVarFlag(var, name) or ''
            if '/' in value or value.startswith('.'):
                bb.fatal("%s[%s] must be a plain file name in the recipe's search path, not '%s'"
                         % (var, name, value))
        if not d.getVarFlag('FLATPAK_REMOTE_URL', name):
            bb.fatal("flatpak remote '%s' has no FLATPAK_REMOTE_URL[%s]" % (name, name))
        key = d.getVarFlag('FLATPAK_REMOTE_GPGKEY', name)
        if key:
            d.appendVar('SRC_URI', ' file://%s' % key)
        elif d.getVarFlag('FLATPAK_REMOTE_NO_GPG', name) != '1':
            bb.fatal("flatpak remote '%s' has no FLATPAK_REMOTE_GPGKEY[%s]; set "
                     "FLATPAK_REMOTE_NO_GPG[%s] = \"1\" to ship it unverified" % (name, name, name))
        if d.getVarFlag('FLATPAK_REMOTE_COLLECTION_ID', name) and not key:
            bb.fatal("flatpak remote '%s': a collection ID requires a GPG key" % name)
        flt = d.getVarFlag('FLATPAK_REMOTE_FILTER', name)
        if flt:
            d.appendVar('SRC_URI', ' file://%s' % flt)
}

# The varflags are read in python; list them so a change rebuilds the recipe.
FLATPAK_REMOTE_VARS = "FLATPAK_REMOTE_URL FLATPAK_REMOTE_TITLE FLATPAK_REMOTE_GPGKEY \
    FLATPAK_REMOTE_COLLECTION_ID FLATPAK_REMOTE_FILTER FLATPAK_REMOTE_NO_GPG"
do_install[vardeps] += "FLATPAK_REMOTES ${FLATPAK_REMOTE_VARS}"

python do_install () {
    import base64
    import os

    unpackdir = d.getVar('UNPACKDIR')
    dest = d.getVar('D')
    remotesdir = os.path.join(dest + d.getVar('sysconfdir'), 'flatpak', 'remotes.d')
    filtersdir = os.path.join(dest + d.getVar('sysconfdir'), 'flatpak', 'filters')
    bb.utils.mkdirhier(remotesdir)

    for name in d.getVar('FLATPAK_REMOTES').split():
        url = d.getVarFlag('FLATPAK_REMOTE_URL', name)
        if not url.startswith('https://'):
            bb.warn("flatpak remote '%s' does not use https: %s" % (name, url))

        lines = ['[Flatpak Repo]', 'Url=%s' % url]
        title = d.getVarFlag('FLATPAK_REMOTE_TITLE', name)
        if title:
            lines.append('Title=%s' % title)

        key = d.getVarFlag('FLATPAK_REMOTE_GPGKEY', name)
        if key:
            with open(os.path.join(unpackdir, key), 'rb') as f:
                data = f.read()
            # flatpak base64-decodes GPGKey and hands the bytes to gpgme as a
            # binary keyring; an armored key would be rejected at runtime.
            if data.lstrip().startswith(b'-----BEGIN'):
                bb.fatal("%s for flatpak remote '%s' is ASCII armored; export it with "
                         "'gpg --export KEYID' (no --armor)" % (key, name))
            # An OpenPGP packet starts with a byte whose top bit is set.
            if not data or not data[0] & 0x80:
                bb.fatal("%s for flatpak remote '%s' is not a binary OpenPGP key" % (key, name))
            lines.append('GPGKey=%s' % base64.b64encode(data).decode('ascii'))
        else:
            bb.warn("flatpak remote '%s' is shipped without a GPG key; nothing pulled "
                    "from it is verified" % name)

        collection_id = d.getVarFlag('FLATPAK_REMOTE_COLLECTION_ID', name)
        if collection_id:
            lines.append('CollectionID=%s' % collection_id)

        flt = d.getVarFlag('FLATPAK_REMOTE_FILTER', name)
        if flt:
            bb.utils.mkdirhier(filtersdir)
            target = os.path.join(filtersdir, '%s.filter' % name)
            with open(os.path.join(unpackdir, flt), 'rb') as src, \
                 open(target, 'wb') as dst:
                dst.write(src.read())
            os.chmod(target, 0o644)
            lines.append('Filter=%s/flatpak/filters/%s.filter' % (d.getVar('sysconfdir'), name))

        path = os.path.join(remotesdir, '%s.flatpakrepo' % name)
        with open(path, 'w') as f:
            f.write('\n'.join(lines) + '\n')
        os.chmod(path, 0o644)
}

RDEPENDS:${PN} = "flatpak"
