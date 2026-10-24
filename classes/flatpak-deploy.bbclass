#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Deploy the flatpak refs a recipe produces, for publishing.
#
# Each producer (flatpak-runtime-image, flatpak-app) puts an ostree archive
# repository holding its refs in ${FLATPAK_DEPLOYDIR}/repo, and
# do_deploy_flatpak deploys it, through sstate, to
#
#   ${FLATPAK_DEPLOY_DIR}/refs/${FLATPAK_DEPLOY_ARCH}/${PN}/
#
# which is ${DEPLOY_DIR}/flatpak/refs/${PACKAGE_ARCH}/${PN}/ unless a
# multiconfig says otherwise (flatpak-common).
#
# A flatpak repository is a feed, like deploy/ipk, not a per-machine image
# artifact: refs are named by flatpak arch and one repository carries all of
# them. The package arch in the path keeps two machines, or two CPU tunes,
# that build the same recipe from colliding; flatpak-repo-index merges every
# producer's refs into the publishable ${DEPLOY_DIR}/flatpak/repo and refuses
# two different commits of one ref.
#
# FLATPAK_DEPLOY_BUNDLES = "1" also deploys each ref as a single-file bundle
# beside the repository, named <id>-<branch>-<arch>.flatpak, for
# 'flatpak install --bundle' on a device without access to the repository.
# A bundle carries the remote it updates from: FLATPAK_DEPLOY_BUNDLE_ORIGIN,
# by default the URL of FLATPAK_BUILD_REMOTE (FLATPAK_REMOTE_URL[remote], as
# flatpak-remotes takes it). Without one it installs, but never updates.
# With FLATPAK_GPGID, it also carries that key, so flatpak verifies the
# commit and its updates.

inherit flatpak-common flatpak-repo

FLATPAK_DEPLOY_REFS_DIR = "${FLATPAK_DEPLOY_DIR}/refs"
FLATPAK_DEPLOYDIR = "${WORKDIR}/deploy-flatpak"

SSTATETASKS += "do_deploy_flatpak"
do_deploy_flatpak[sstate-inputdirs] = "${FLATPAK_DEPLOYDIR}"
do_deploy_flatpak[sstate-outputdirs] = "${FLATPAK_DEPLOY_REFS_DIR}/${FLATPAK_DEPLOY_ARCH}/${PN}"

python do_deploy_flatpak_setscene () {
    sstate_setscene(d)
}
addtask do_deploy_flatpak_setscene

FLATPAK_DEPLOY_BUNDLES ??= "0"
FLATPAK_DEPLOY_BUNDLE_ORIGIN ??= "${@(d.getVarFlag('FLATPAK_REMOTE_URL', d.getVar('FLATPAK_BUILD_REMOTE')) or '') if d.getVar('FLATPAK_BUILD_REMOTE') else ''}"

DEPENDS += "${@'flatpak-build-bundle-native' if bb.utils.to_boolean(d.getVar('FLATPAK_DEPLOY_BUNDLES')) else ''}"

python flatpak_deploy_bundles () {
    import subprocess

    if not bb.utils.to_boolean(d.getVar('FLATPAK_DEPLOY_BUNDLES')):
        return
    deploydir = d.getVar('FLATPAK_DEPLOYDIR')
    repo = os.path.join(deploydir, 'repo')
    origin = d.getVar('FLATPAK_DEPLOY_BUNDLE_ORIGIN')
    if origin and not origin.startswith('https://'):
        bb.fatal("FLATPAK_DEPLOY_BUNDLE_ORIGIN must be an https URL, not '%s'" % origin)

    args = []
    if origin:
        args.append('--origin=%s' % origin)
    if d.getVar('SOURCE_DATE_EPOCH'):
        args.append('--timestamp=%s' % d.getVar('SOURCE_DATE_EPOCH'))
    env = dict(os.environ)
    env['PATH'] = '%s:%s' % (d.getVar('STAGING_BINDIR_NATIVE'), env.get('PATH', ''))
    env['PSEUDO_UNLOAD'] = '1'
    if d.getVar('FLATPAK_GPGID'):
        keys = os.path.join(d.getVar('WORKDIR'), 'flatpak-bundle-keys.gpg')
        with open(keys, 'wb') as f:
            proc = subprocess.run(['gpg', '--homedir', d.getVar('FLATPAK_GPGHOME'), '--export',
                                   d.getVar('FLATPAK_GPGID')], env=env, stdout=f, stderr=subprocess.PIPE)
        if proc.returncode != 0 or not os.path.getsize(keys):
            bb.fatal("exporting the public key of FLATPAK_GPGID %s failed:\n%s"
                     % (d.getVar('FLATPAK_GPGID'), proc.stderr.decode(errors='replace')))
        args.append('--gpg-keys=%s' % keys)

    for ref in flatpak_repo_ostree(d, ['--repo=%s' % repo, 'refs']).split():
        _, ref_id, arch, branch = ref.split('/')
        name = '%s-%s-%s.flatpak' % (ref_id, branch, arch)
        proc = subprocess.run(['flatpak-build-bundle', '--repo=%s' % repo, '--ref=%s' % ref] + args +
                              [os.path.join(deploydir, name)],
                              env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if proc.returncode != 0:
            bb.fatal("bundling %s failed:\n%s" % (ref, proc.stdout))
        bb.note("Bundled %s as %s" % (ref, name))
}
flatpak_deploy_bundles[vardeps] += "FLATPAK_DEPLOY_BUNDLES FLATPAK_DEPLOY_BUNDLE_ORIGIN FLATPAK_GPGID"
flatpak_deploy_bundles[vardepsexclude] += "FLATPAK_GPGHOME"
# Static, so sstate's anonymous function still puts its capture after it.
do_deploy_flatpak[postfuncs] += "flatpak_deploy_bundles"
