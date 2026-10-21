#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Publishable flatpak repository of the refs this build produced"
DESCRIPTION = "Merges the refs every flatpak producer deployed under \
               ${DEPLOY_DIR}/flatpak/refs into one ostree repository, \
               ${DEPLOY_DIR}/flatpak/repo, ready to sync to the remote \
               devices update from. The flatpak counterpart of package-index: \
               build the producers, then run it."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

INHIBIT_DEFAULT_DEPS = "1"
PACKAGES = ""

inherit nopackages flatpak-repo

deltask do_fetch
deltask do_unpack
deltask do_patch
deltask do_configure
deltask do_compile
deltask do_install
deltask do_populate_lic
deltask do_populate_sysroot

FLATPAK_PUBLISH_REFS_DIR = "${DEPLOY_DIR}/flatpak/refs"
FLATPAK_PUBLISH_REPO = "${DEPLOY_DIR}/flatpak/repo"

# Package archs (directories under refs/) to publish; empty publishes all.
# Two builds of one ref for different CPU tunes or machines give different
# commits, and a repository holds one per ref: name the build to publish.
FLATPAK_PUBLISH_PACKAGE_ARCHS ??= ""

# Recipes to build first; their refs are published either way once deployed.
FLATPAK_PUBLISH_RECIPES ??= ""

# Static deltas to generate for each ref that changed:
#   previous  from the commit published before, so an update is a few files
#             instead of every changed object
#   empty     from scratch, for installs over the network; about doubles
#             the repository's size
# Devices here get their first install at build time, so only previous by
# default. A delta lives as long as the commit it leads to.
FLATPAK_PUBLISH_DELTAS ??= "previous"

python () {
    for word in (d.getVar('FLATPAK_PUBLISH_DELTAS') or '').split():
        if word not in ('previous', 'empty'):
            bb.fatal("FLATPAK_PUBLISH_DELTAS: unknown '%s'; use previous and/or empty" % word)
    for pn in (d.getVar('FLATPAK_PUBLISH_RECIPES') or '').split():
        d.appendVarFlag('do_flatpak_repo_index', 'depends', ' %s:do_deploy_flatpak' % pn)
}

python do_flatpak_repo_index () {
    refs_dir = d.getVar('FLATPAK_PUBLISH_REFS_DIR')
    repo = d.getVar('FLATPAK_PUBLISH_REPO')
    archs = (d.getVar('FLATPAK_PUBLISH_PACKAGE_ARCHS') or '').split()

    sources = []
    for arch in sorted(os.listdir(refs_dir)) if os.path.isdir(refs_dir) else []:
        if archs and arch not in archs:
            continue
        for pn in sorted(os.listdir(os.path.join(refs_dir, arch))):
            src = os.path.join(refs_dir, arch, pn, 'repo')
            if os.path.isfile(os.path.join(src, 'config')):
                sources.append(('%s/%s' % (arch, pn), src))
    if not sources:
        bb.fatal("no flatpak refs deployed under %s%s; build the producers first"
                 % (refs_dir, ' for %s' % ' '.join(archs) if archs else ''))

    # One commit per ref: a ref built twice differently is a choice to make.
    owner = {}
    for name, src in sources:
        for ref in flatpak_repo_ostree(d, ['--repo=%s' % src, 'refs']).split():
            commit = flatpak_repo_ostree(d, ['--repo=%s' % src, 'rev-parse', ref]).strip()
            if ref in owner and owner[ref][0] != commit:
                bb.fatal("%s is deployed by %s and %s at different commits; set "
                         "FLATPAK_PUBLISH_PACKAGE_ARCHS to the package archs to publish"
                         % (ref, owner[ref][1], name))
            owner[ref] = (commit, name)

    flatpak_repo_check_signing(d)
    lock = bb.utils.lockfile(repo + '.lock')
    try:
        if not os.path.isfile(os.path.join(repo, 'config')):
            bb.utils.mkdirhier(repo)
            flatpak_repo_ostree(d, ['--repo=%s' % repo, 'init', '--mode=archive'])
        flatpak_repo_ostree(d, ['--repo=%s' % repo, 'config', 'set', 'core.min-free-space-size',
                                d.getVar('FLATPAK_REPO_MIN_FREE')])
        # What devices have now, while its objects are still here.
        published = {}
        for ref in flatpak_repo_ostree(d, ['--repo=%s' % repo, 'refs']).split():
            published[ref] = flatpak_repo_ostree(d, ['--repo=%s' % repo, 'rev-parse', ref]).strip()
        for name, src in sources:
            flatpak_repo_ostree(d, ['--repo=%s' % repo, 'pull-local', src] +
                                flatpak_repo_ostree(d, ['--repo=%s' % src, 'refs']).split())
        kinds = (d.getVar('FLATPAK_PUBLISH_DELTAS') or '').split()
        existing = set(flatpak_repo_ostree(d, ['--repo=%s' % repo, 'static-delta', 'list']).split())
        for ref, (commit, name) in sorted(owner.items()):
            old = published.get(ref)
            if 'previous' in kinds and old and old != commit and '%s-%s' % (old, commit) not in existing:
                flatpak_repo_ostree(d, ['--repo=%s' % repo, 'static-delta', 'generate',
                                        '--from=%s' % old, '--to=%s' % commit])
                bb.note("delta %s: %s -> %s" % (ref, old, commit))
            if 'empty' in kinds and commit not in existing:
                flatpak_repo_ostree(d, ['--repo=%s' % repo, 'static-delta', 'generate',
                                        '--empty', '--to=%s' % commit])
                bb.note("delta %s: from scratch -> %s" % (ref, commit))

        # Devices fetch the current commit of each ref; older ones are no
        # longer referenced. Pruning them also drops the deltas that led to
        # them.
        flatpak_repo_ostree(d, ['--repo=%s' % repo, 'prune', '--refs-only'])
        bb.utils.remove(os.path.join(repo, 'summary.sig'))
        args = ['--repo=%s' % repo, 'summary', '--update']
        if d.getVar('FLATPAK_GPGID'):
            args += ['--gpg-sign=%s' % d.getVar('FLATPAK_GPGID'), '--gpg-homedir=%s' % d.getVar('FLATPAK_GPGHOME')]
        else:
            bb.warn("%s has an unsigned summary: set FLATPAK_GPGID to sign it, or devices that "
                    "verify the remote's summary refuse it" % repo)
        flatpak_repo_ostree(d, args)
        flatpak_repo_ostree(d, ['--repo=%s' % repo, 'fsck', '--quiet'])
    finally:
        bb.utils.unlockfile(lock)

    for ref, (commit, name) in sorted(owner.items()):
        bb.note("%s %s (%s)" % (ref, commit, name))
}
do_flatpak_repo_index[nostamp] = "1"
do_flatpak_repo_index[vardepsexclude] += "FLATPAK_GPGHOME"
addtask do_flatpak_repo_index after do_prepare_recipe_sysroot before do_build

EXCLUDE_FROM_WORLD = "1"
