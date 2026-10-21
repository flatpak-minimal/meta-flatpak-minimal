#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Package flatpak content built outside this build so flatpak-cross-install
# can install it into the image's system installation at build time.
#
# A recipe provides one of three kinds of input:
#
#   Refs mirrored from a remote, pinned by commit:
#
#     FLATPAK_REMOTE = "flathub"
#     FLATPAK_REMOTE_URL = "https://dl.flathub.org/repo/"
#     FLATPAK_REMOTE_GPGKEY = "flathub.gpg"
#     FLATPAK_REMOTE_REFS = "runtime/org.freedesktop.Platform/aarch64/25.08@ef5f18ba..."
#
#   Each entry is REF@COMMIT. The commits are pulled with ostree-native into
#   a mirror under DL_DIR during do_fetch, verified against the GPG key and
#   against the ref each commit is bound to, and copied into a repository
#   that ships with the package. The pin is what makes the build
#   reproducible: the commit checksum covers the whole tree.
#
#   A single-file bundle (flatpak build-bundle):
#
#     SRC_URI = "https://.../app.flatpak;downloadfilename=...;name=bundle"
#     SRC_URI[bundle.sha256sum] = "..."
#     FLATPAK_BUNDLE_FILE = "app.flatpak"
#     FLATPAK_BUNDLE_REF = "app/org.example.App/aarch64/stable"
#
#   A bundle built with 'flatpak build-bundle --repo-url=...' carries the
#   remote it updates from, and installs under that origin. One built without
#   it installs, but can never be updated in the field; flatpak-cross-install
#   refuses it unless FLATPAK_BUNDLE_ALLOW_NO_ORIGIN = "1".
#
#   A runtime built by this build (flatpak-runtime-image):
#
#     FLATPAK_IMAGE = "flutter-platform-runtime-image"
#
#   The image's deployed repository is copied whole. FLATPAK_REMOTE defaults
#   to FLATPAK_BUILD_REMOTE. LICENSE must name every license of the packages
#   in the runtime: do_compile checks it against the list the image deploys
#   and says what is missing. LIC_FILES_CHKSUM defaults to the common license
#   texts of those licenses.
#
# For mirrored and built refs, FLATPAK_REMOTE names the remote the content is installed
# under, and so the origin it is updated from on the device. It must match a
# remote shipped by flatpak-remotes.
#
# The package carries, under ${datadir}/flatpak-bundles:
#   repos/${PN}/          ostree archive repository (mirrored or built refs)
#   bundles/${PN}/FILE    the bundle (bundle input)
#   ${PN}.refs            one "REF COMMIT" line per ref ("-" for a bundle)
#   ${PN}.meta            key=value properties for flatpak-cross-install

inherit flatpak-common

FLATPAK_REMOTE ??= ""
FLATPAK_REMOTE_URL ??= ""
FLATPAK_REMOTE_GPGKEY ??= ""
FLATPAK_REMOTE_REFS ??= ""
FLATPAK_BUNDLE_FILE ??= ""
FLATPAK_BUNDLE_REF ??= ""
FLATPAK_BUNDLE_ALLOW_NO_ORIGIN ??= "0"
FLATPAK_IMAGE ??= ""
FLATPAK_BUILD_REMOTE ??= ""
# Where flatpak-runtime-image deploys (flatpak-deploy.bbclass); an image's
# package arch is the machine's.
FLATPAK_IMAGE_DEPLOY = "${DEPLOY_DIR}/flatpak/refs/${MACHINE_ARCH}/${FLATPAK_IMAGE}"
FLATPAK_IMAGE_REPO = "${FLATPAK_IMAGE_DEPLOY}/repo"

# Flathub's CDN refuses requests whose user agent names libostree, which is
# ostree's default.
FLATPAK_MIRROR_USER_AGENT ??= "meta-flatpak-minimal/1.0"

# Shared by every recipe mirroring from the same remote; ostree stores each
# object once, and a pinned commit already present is never fetched again.
FLATPAK_MIRROR_DIR ??= "${DL_DIR}/flatpak-mirror"

DEPENDS += "ostree-native"

S = "${UNPACKDIR}"

python () {
    import re

    refs = (d.getVar('FLATPAK_REMOTE_REFS') or '').split()
    bundle = d.getVar('FLATPAK_BUNDLE_FILE')
    image = d.getVar('FLATPAK_IMAGE')
    remote = d.getVar('FLATPAK_REMOTE')

    if len([x for x in (refs, bundle, image) if x]) > 1:
        bb.fatal("set only one of FLATPAK_REMOTE_REFS, FLATPAK_BUNDLE_FILE and FLATPAK_IMAGE")
    if not refs and not bundle and not image:
        # Usually refs pinned only for some architectures through overrides.
        raise bb.parse.SkipRecipe("no flatpak content for flatpak arch %s" % d.getVar('FLATPAK_ARCH'))

    if image:
        if not remote:
            remote = d.getVar('FLATPAK_BUILD_REMOTE')
            if not remote:
                raise bb.parse.SkipRecipe("set FLATPAK_BUILD_REMOTE to the remote refs built here "
                                          "install under")
            d.setVar('FLATPAK_REMOTE', remote)
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', remote):
            bb.fatal("FLATPAK_REMOTE '%s' is not a remote name" % remote)
        d.appendVarFlag('do_compile', 'depends', ' %s:do_deploy_flatpak' % image)
        d.appendVarFlag('do_compile', 'prefuncs', ' flatpak_bundle_check_licenses')
        # The image is built for this machine.
        d.setVar('PACKAGE_ARCH', d.getVar('MACHINE_ARCH'))
        if not d.getVar('LIC_FILES_CHKSUM'):
            # The licenses' texts, as the common license directory has them.
            files = []
            for name in sorted(flatpak_license_names(d.getVar('LICENSE'))):
                path = os.path.join(d.getVar('COMMON_LICENSE_DIR'), name)
                if os.path.isfile(path):
                    files.append('file://%s;md5=%s' % (path, bb.utils.md5_file(path)))
            d.setVar('LIC_FILES_CHKSUM', ' '.join(files))
        return

    ref_re = r'(app|runtime)/[A-Za-z0-9._-]+/[A-Za-z0-9_]+/[A-Za-z0-9._-]+'
    if bundle:
        if remote:
            bb.fatal("FLATPAK_REMOTE does not apply to a bundle: it installs under the origin "
                     "it was built with (flatpak build-bundle --repo-url)")
        if '/' in bundle:
            bb.fatal("FLATPAK_BUNDLE_FILE must be a plain file name")
        if not re.fullmatch(ref_re, d.getVar('FLATPAK_BUNDLE_REF') or ''):
            bb.fatal("FLATPAK_BUNDLE_REF must be a full ref, e.g. app/org.example.App/aarch64/stable")
        return

    for entry in refs:
        ref, _, commit = entry.partition('@')
        if not re.fullmatch(ref_re, ref):
            bb.fatal("FLATPAK_REMOTE_REFS: '%s' is not a full ref" % ref)
        if not re.fullmatch(r'[0-9a-f]{64}', commit):
            bb.fatal("FLATPAK_REMOTE_REFS: '%s' needs a pinned commit (REF@64-hex-digit checksum)" % entry)
        if ref.split('/')[2] != d.getVar('FLATPAK_ARCH'):
            raise bb.parse.SkipRecipe("%s is not for flatpak arch %s" % (ref, d.getVar('FLATPAK_ARCH')))

    if not remote or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', remote):
        bb.fatal("FLATPAK_REMOTE must name the remote the content installs under")

    url = d.getVar('FLATPAK_REMOTE_URL') or ''
    if not url.startswith('https://'):
        bb.fatal("FLATPAK_REMOTE_URL must be an https URL, not '%s'" % url)
    key = d.getVar('FLATPAK_REMOTE_GPGKEY')
    if key:
        if '/' in key:
            bb.fatal("FLATPAK_REMOTE_GPGKEY must be a plain file name in the recipe's search path")
        d.appendVar('SRC_URI', ' file://%s' % key)
        d.appendVarFlag('do_fetch', 'depends', ' gnupg-native:do_populate_sysroot')

    # ostree must be usable inside do_fetch, which runs before the recipe
    # sysroot is normally prepared; network access stays within do_fetch.
    d.appendVarFlag('do_fetch', 'depends', ' ostree-native:do_populate_sysroot')
    d.appendVarFlag('do_fetch', 'prefuncs', ' extend_recipe_sysroot')
    d.appendVarFlag('do_fetch', 'postfuncs', ' flatpak_bundle_mirror')
}

python flatpak_bundle_check_licenses () {
    path = os.path.join(d.getVar('FLATPAK_IMAGE_DEPLOY'), 'licenses')
    if not os.path.isfile(path):
        bb.fatal("%s deployed no license list at %s" % (d.getVar('FLATPAK_IMAGE'), path))
    with open(path) as f:
        runtime = set(f.read().split())
    declared = flatpak_license_names(d.getVar('LICENSE'))
    missing = sorted(runtime - declared)
    if missing:
        bb.fatal("LICENSE does not name every license in %s; missing: %s. The runtime's licenses are:\n"
                 "LICENSE = \"%s\"" % (d.getVar('FLATPAK_IMAGE'), ' '.join(missing), ' & '.join(sorted(runtime))))
    unused = sorted(declared - runtime)
    if unused:
        bb.warn("LICENSE names licenses no package in %s has: %s" % (d.getVar('FLATPAK_IMAGE'), ' '.join(unused)))
}

def flatpak_bundle_ostree(d, args, **kwargs):
    import subprocess
    env = dict(os.environ)
    env['PATH'] = '%s:%s:%s' % (d.getVar('STAGING_BINDIR_NATIVE'), d.getVar('STAGING_SBINDIR_NATIVE'), env.get('PATH', ''))
    return subprocess.run([os.path.join(d.getVar('STAGING_BINDIR_NATIVE'), 'ostree')] + args,
                          env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, **kwargs).stdout

def flatpak_bundle_has_commit(d, repo, commit):
    import subprocess
    try:
        flatpak_bundle_ostree(d, ['--repo=%s' % repo, 'show', commit])
        return True
    except subprocess.CalledProcessError:
        return False

python flatpak_bundle_mirror () {
    import subprocess

    remote = d.getVar('FLATPAK_REMOTE')
    mirror = os.path.join(d.getVar('FLATPAK_MIRROR_DIR'), remote)
    repo = os.path.join(mirror, 'repo')
    bb.utils.mkdirhier(mirror)

    keyfile = None
    key = d.getVar('FLATPAK_REMOTE_GPGKEY')
    if key:
        fetcher = bb.fetch2.Fetch(['file://%s' % key], d)
        keyfile = fetcher.localpath('file://%s' % key)

    lock = bb.utils.lockfile(os.path.join(mirror, 'lock'))
    try:
        if not os.path.exists(os.path.join(repo, 'config')):
            flatpak_bundle_ostree(d, ['--repo=%s' % repo, 'init', '--mode=archive'])
        flatpak_bundle_ostree(d, ['--repo=%s' % repo, 'config', 'set', 'core.min-free-space-size',
                                  d.getVar('FLATPAK_REPO_MIN_FREE')])

        # Reconfigure the remote every time, so a changed URL or key in the
        # recipe takes effect and a stale one cannot verify anything.
        flatpak_bundle_ostree(d, ['--repo=%s' % repo, 'remote', 'delete', '--if-exists', remote])
        add = ['--repo=%s' % repo, 'remote', 'add']
        add += ['--gpg-import=%s' % keyfile] if keyfile else ['--no-gpg-verify']
        flatpak_bundle_ostree(d, add + [remote, d.getVar('FLATPAK_REMOTE_URL')])
        if not keyfile:
            bb.warn("%s: mirroring from '%s' without GPG verification; only the pinned "
                    "commit checksum protects the content" % (d.getVar('PN'), remote))

        for entry in d.getVar('FLATPAK_REMOTE_REFS').split():
            ref, _, commit = entry.partition('@')
            if not flatpak_bundle_has_commit(d, repo, commit):
                if bb.utils.to_boolean(d.getVar('BB_NO_NETWORK')):
                    bb.fatal("%s is not in the flatpak mirror %s and BB_NO_NETWORK is set" % (entry, repo))
                bb.note("Pulling %s from %s" % (entry, remote))
                try:
                    out = flatpak_bundle_ostree(d, ['--repo=%s' % repo, 'pull', '--depth=0',
                        '--http-header=User-Agent=%s' % d.getVar('FLATPAK_MIRROR_USER_AGENT'),
                        remote, commit])
                    bb.note(out.strip())
                except subprocess.CalledProcessError as e:
                    bb.fatal("pulling %s from %s failed:\n%s" % (entry, remote, e.stdout))

            # A pin copied from the wrong ref would otherwise install under
            # the right name.
            binding = flatpak_bundle_ostree(d, ['--repo=%s' % repo, 'show',
                '--print-metadata-key=ostree.ref-binding', commit]).strip()
            if "'%s'" % ref not in binding:
                bb.fatal("commit %s is bound to %s, not to %s" % (commit, binding, ref))
    finally:
        bb.utils.unlockfile(lock)
}

do_compile () {
    rm -rf ${B}/repo ${B}/refs
    if [ -n "${FLATPAK_REMOTE_REFS}" ]; then
        mirror=${FLATPAK_MIRROR_DIR}/${FLATPAK_REMOTE}/repo
        ostree --repo=${B}/repo init --mode=archive
        ostree --repo=${B}/repo config set core.min-free-space-size ${FLATPAK_REPO_MIN_FREE}
        for entry in ${FLATPAK_REMOTE_REFS}; do
            ref=${entry%@*}
            commit=${entry#*@}
            # Copies the commit, its tree and its detached signatures.
            ostree --repo=${B}/repo pull-local --depth=0 $mirror $commit
            ostree --repo=${B}/repo refs --create=$ref $commit
            echo "$ref $commit" >> ${B}/refs
        done
        ostree --repo=${B}/repo summary --update
        ostree --repo=${B}/repo fsck --quiet
    elif [ -n "${FLATPAK_IMAGE}" ]; then
        src=${FLATPAK_IMAGE_REPO}
        [ -f $src/config ] || bbfatal "${FLATPAK_IMAGE} deployed no flatpak repository at $src"
        ostree --repo=${B}/repo init --mode=archive
        ostree --repo=${B}/repo config set core.min-free-space-size ${FLATPAK_REPO_MIN_FREE}
        for ref in $(ostree --repo=$src refs); do
            commit=$(ostree --repo=$src rev-parse $ref)
            ostree --repo=${B}/repo pull-local --depth=0 $src $ref
            echo "$ref $commit" >> ${B}/refs
        done
        [ -s ${B}/refs ] || bbfatal "$src holds no refs"
        ostree --repo=${B}/repo summary --update
        ostree --repo=${B}/repo fsck --quiet
    else
        [ -f ${UNPACKDIR}/${FLATPAK_BUNDLE_FILE} ] || bbfatal "bundle ${FLATPAK_BUNDLE_FILE} not found in UNPACKDIR"
        echo "${FLATPAK_BUNDLE_REF} -" > ${B}/refs
    fi
}

do_install () {
    dest=${D}${FLATPAK_BUNDLES_DIR}
    install -d $dest
    if [ -n "${FLATPAK_REMOTE_REFS}${FLATPAK_IMAGE}" ]; then
        install -d $dest/repos
        cp -R --no-preserve=ownership ${B}/repo $dest/repos/${PN}
        kind=repo
        path=repos/${PN}
    else
        install -D -m 0644 ${UNPACKDIR}/${FLATPAK_BUNDLE_FILE} $dest/bundles/${PN}/${FLATPAK_BUNDLE_FILE}
        kind=bundle
        path=bundles/${PN}/${FLATPAK_BUNDLE_FILE}
    fi
    install -m 0644 ${B}/refs $dest/${PN}.refs
    printf 'kind=%s\npath=%s\nremote=%s\nallow_no_origin=%s\n' \
        "$kind" "$path" "${FLATPAK_REMOTE}" "${FLATPAK_BUNDLE_ALLOW_NO_ORIGIN}" > $dest/${PN}.meta
    chmod 0644 $dest/${PN}.meta
}

do_compile[vardeps] += "FLATPAK_REMOTE_REFS FLATPAK_REMOTE FLATPAK_BUNDLE_FILE FLATPAK_BUNDLE_REF FLATPAK_IMAGE"
do_install[vardeps] += "FLATPAK_BUNDLE_ALLOW_NO_ORIGIN"

do_configure[noexec] = "1"

FILES:${PN} += "${FLATPAK_BUNDLES_DIR}"
