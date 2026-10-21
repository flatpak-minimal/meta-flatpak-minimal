#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Package what a recipe installs as a flatpak app, alongside its normal
# packages.
#
#   inherit flatpak-app
#   FLATPAK_APP_ID = "org.example.App"
#   FLATPAK_APP_RUNTIME = "org.example.Platform"
#   FLATPAK_APP_RUNTIME_BRANCH = "1.0"
#   FLATPAK_APP_RUNTIME_PACKAGE = "example-platform-runtime"
#   FLATPAK_APP_FILES = "${datadir}/example"
#   FLATPAK_APP_COMMAND = "example-viewer --data=${datadir}/example"
#   FLATPAK_APP_FINISH_ARGS = "--socket=wayland --device=dri"
#
# After do_install, the paths in FLATPAK_APP_FILES (all under ${prefix}) are
# copied out of ${D} into the app's files/, which flatpak mounts at /app, so
# ${prefix}/X becomes /app/X. Paths in FLATPAK_APP_COMMAND and
# FLATPAK_APP_LIBDIRS are translated the same way. A symlink that points
# outside FLATPAK_APP_FILES is made absolute, so it resolves into the
# runtime's /usr.
#
# The app is committed as app/ID/ARCH/BRANCH (flatpak-repo.bbclass), deployed
# for publishing to ${DEPLOY_DIR}/flatpak/refs/<package arch>/${PN}/repo
# (flatpak-deploy.bbclass), and ships in ${PN}-flatpak under
# ${FLATPAK_BUNDLES_DIR}, in the form flatpak-bundle uses, so
# 'IMAGE_INSTALL += "${PN}-flatpak"' or BUNDLED_FLATPAKS installs it through
# flatpak-cross-install. ${PN}-flatpak depends on
# FLATPAK_APP_RUNTIME_PACKAGE, which carries the runtime the same way.
#
# FLATPAK_APP_COMMAND is a command line run by /bin/sh from the runtime; a
# single word is used as the app's command directly.
# FLATPAK_APP_FINISH_ARGS takes flatpak-builder finish-args: --share,
# --socket, --device, --allow, --filesystem, --persist (and their negations),
# --env, --talk-name, --own-name, --see-name and their --system- forms.
# FLATPAK_APP_LIBDIRS are added to the app's linker cache, which finds
# libraries by soname. A library opened by a bare file name that is not its
# soname (dlopen("libfoo.so")) is only found through LD_LIBRARY_PATH: list its
# directory in FLATPAK_APP_LD_LIBRARY_PATH, which the launcher exports.

inherit flatpak-repo flatpak-deploy

FLATPAK_APP_ID ??= ""
FLATPAK_APP_BRANCH ??= "stable"
FLATPAK_APP_RUNTIME ??= ""
FLATPAK_APP_RUNTIME_BRANCH ??= ""
FLATPAK_APP_RUNTIME_PACKAGE ??= ""
FLATPAK_APP_FILES ??= ""
FLATPAK_APP_COMMAND ??= ""
FLATPAK_APP_FINISH_ARGS ??= ""
FLATPAK_APP_LIBDIRS ??= ""
FLATPAK_APP_LD_LIBRARY_PATH ??= ""
FLATPAK_REMOTE ??= "${FLATPAK_BUILD_REMOTE}"

FLATPAK_APP_REF = "app/${FLATPAK_APP_ID}/${FLATPAK_ARCH}/${FLATPAK_APP_BRANCH}"
FLATPAK_APP_PACKAGE = "${PN}-flatpak"
# The wrapper FLATPAK_APP_COMMAND runs through, in /app/bin.
FLATPAK_APP_LAUNCHER = "vfpk-launch"

PACKAGES =+ "${FLATPAK_APP_PACKAGE}"
FILES:${FLATPAK_APP_PACKAGE} = "\
    ${FLATPAK_BUNDLES_DIR}/repos/${FLATPAK_APP_PACKAGE} \
    ${FLATPAK_BUNDLES_DIR}/${FLATPAK_APP_PACKAGE}.refs \
    ${FLATPAK_BUNDLES_DIR}/${FLATPAK_APP_PACKAGE}.meta \
"
RDEPENDS:${FLATPAK_APP_PACKAGE} = "${FLATPAK_APP_RUNTIME_PACKAGE}"

python () {
    import re

    if not d.getVar('FLATPAK_ARCH'):
        raise bb.parse.SkipRecipe("flatpak has no arch for TARGET_ARCH %s" % d.getVar('TARGET_ARCH'))
    if not d.getVar('FLATPAK_REMOTE'):
        raise bb.parse.SkipRecipe("set FLATPAK_BUILD_REMOTE to the remote refs built here install under")
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', d.getVar('FLATPAK_REMOTE')):
        bb.fatal("FLATPAK_REMOTE '%s' is not a remote name" % d.getVar('FLATPAK_REMOTE'))
    for var in ('FLATPAK_APP_ID', 'FLATPAK_APP_RUNTIME'):
        if not re.fullmatch(d.getVar('FLATPAK_ID_RE'), d.getVar(var) or ''):
            bb.fatal("%s '%s' is not a flatpak ID (reverse DNS, three parts or more)" % (var, d.getVar(var)))
    for var in ('FLATPAK_APP_BRANCH', 'FLATPAK_APP_RUNTIME_BRANCH'):
        if not re.fullmatch(d.getVar('FLATPAK_BRANCH_RE'), d.getVar(var) or ''):
            bb.fatal("%s '%s' is not a flatpak branch" % (var, d.getVar(var)))
    if not d.getVar('FLATPAK_APP_RUNTIME_PACKAGE'):
        bb.fatal("FLATPAK_APP_RUNTIME_PACKAGE must name the package carrying the runtime")
    command = d.getVar('FLATPAK_APP_COMMAND') or ''
    if not command.strip() or '\n' in command:
        bb.fatal("FLATPAK_APP_COMMAND must be a one-line command")
    prefix = d.getVar('prefix')
    for path in (d.getVar('FLATPAK_APP_FILES') or '').split() + (d.getVar('FLATPAK_APP_LIBDIRS') or '').split() + \
                (d.getVar('FLATPAK_APP_LD_LIBRARY_PATH') or '').split():
        if not path.startswith(prefix + '/') or '..' in path.split('/'):
            bb.fatal("'%s' is not under ${prefix} (%s)" % (path, prefix))
    if not d.getVar('FLATPAK_APP_FILES'):
        bb.fatal("FLATPAK_APP_FILES is empty")
    flatpak_repo_check_signing(d)
}

def flatpak_app_path(d, path):
    """The path an installed ${prefix} path has in the sandbox."""
    return '/app' + path[len(d.getVar('prefix')):]

python flatpak_app_commit () {
    import re
    import shutil

    dest = d.getVar('D')
    prefix = d.getVar('prefix')
    work = os.path.join(d.getVar('WORKDIR'), 'flatpak-app')
    tree = os.path.join(work, 'tree')
    repo = os.path.join(work, 'repo')
    bb.utils.remove(work, recurse=True)
    files = os.path.join(tree, 'files')
    bb.utils.mkdirhier(files)

    roots = (d.getVar('FLATPAK_APP_FILES') or '').split()
    for root in roots:
        src = dest + root
        if not os.path.isdir(src) and not os.path.isfile(src):
            bb.fatal("FLATPAK_APP_FILES: %s was not installed" % root)
        target = os.path.join(files, root[len(prefix) + 1:])
        bb.utils.mkdirhier(os.path.dirname(target))
        if os.path.isdir(src):
            shutil.copytree(src, target, symlinks=True)
        else:
            shutil.copy2(src, target, follow_symlinks=False)

    # A symlink into the rest of ${prefix} has nothing to point at under
    # /app; pointed at /usr, it finds the runtime's copy.
    def inside(path):
        return any(path == r or path.startswith(r + '/') for r in roots)
    for top, dirs, names in os.walk(files):
        for name in dirs + names:
            link = os.path.join(top, name)
            if not os.path.islink(link):
                continue
            installed = prefix + '/' + os.path.relpath(link, files)
            target = os.path.normpath(os.path.join(os.path.dirname(installed), os.readlink(link)))
            if not inside(target):
                os.unlink(link)
                os.symlink(target, link)
                bb.note("%s now points to %s in the runtime" % (installed, target))

    command = d.getVar('FLATPAK_APP_COMMAND').strip()
    for path in sorted(roots, key=len, reverse=True):
        command = re.sub(r'(?<![^\s=])%s(?=/|\s|$)' % re.escape(path), flatpak_app_path(d, path), command)
    ld_path = ':'.join(flatpak_app_path(d, p) for p in (d.getVar('FLATPAK_APP_LD_LIBRARY_PATH') or '').split())
    if len(command.split()) > 1 or ld_path:
        launcher = os.path.join(files, 'bin', d.getVar('FLATPAK_APP_LAUNCHER'))
        bb.utils.mkdirhier(os.path.dirname(launcher))
        with open(launcher, 'w') as f:
            f.write('#!/bin/sh\n')
            if ld_path:
                f.write('export LD_LIBRARY_PATH=%s${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\n' % ld_path)
            f.write('exec %s "$@"\n' % command)
        os.chmod(launcher, 0o755)
        command = d.getVar('FLATPAK_APP_LAUNCHER')

    libdirs = [flatpak_app_path(d, p) for p in (d.getVar('FLATPAK_APP_LIBDIRS') or '').split()]
    if libdirs:
        # flatpak includes /app/etc/ld.so.conf in the sandbox's linker cache.
        bb.utils.mkdirhier(os.path.join(files, 'etc'))
        with open(os.path.join(files, 'etc', 'ld.so.conf'), 'w') as f:
            f.write('\n'.join(libdirs) + '\n')

    runtime = '%s/%s/%s' % (d.getVar('FLATPAK_APP_RUNTIME'), d.getVar('FLATPAK_ARCH'),
                            d.getVar('FLATPAK_APP_RUNTIME_BRANCH'))
    with open(os.path.join(tree, 'metadata'), 'w') as f:
        f.write('[Application]\nname=%s\nruntime=%s\ncommand=%s\n'
                % (d.getVar('FLATPAK_APP_ID'), runtime, command))
        f.write(flatpak_repo_finish_args(d, d.getVar('FLATPAK_APP_FINISH_ARGS') or ''))

    ref = d.getVar('FLATPAK_APP_REF')
    commit = flatpak_repo_commit(d, repo, ref, tree, '%s %s' % (d.getVar('PN'), d.getVar('PV')))
    bb.note("Committed %s as %s" % (ref, commit))

    package = d.getVar('FLATPAK_APP_PACKAGE')
    bundles = dest + d.getVar('FLATPAK_BUNDLES_DIR')
    bb.utils.mkdirhier(os.path.join(bundles, 'repos'))
    shutil.copytree(repo, os.path.join(bundles, 'repos', package), symlinks=True)
    with open(os.path.join(bundles, package + '.refs'), 'w') as f:
        f.write('%s %s\n' % (ref, commit))
    with open(os.path.join(bundles, package + '.meta'), 'w') as f:
        f.write('kind=repo\npath=repos/%s\nremote=%s\nallow_no_origin=0\n'
                % (package, d.getVar('FLATPAK_REMOTE')))
    bb.utils.remove(work, recurse=True)
}
do_install[postfuncs] += "flatpak_app_commit"
do_install[vardeps] += "FLATPAK_APP_ID FLATPAK_APP_BRANCH FLATPAK_APP_RUNTIME FLATPAK_APP_RUNTIME_BRANCH \
    FLATPAK_APP_FILES FLATPAK_APP_COMMAND FLATPAK_APP_FINISH_ARGS FLATPAK_APP_LIBDIRS \
    FLATPAK_APP_LD_LIBRARY_PATH FLATPAK_REMOTE \
    FLATPAK_GPGID"
do_install[vardepsexclude] += "FLATPAK_GPGHOME"

python do_deploy_flatpak () {
    import shutil
    src = os.path.join(d.getVar('D') + d.getVar('FLATPAK_BUNDLES_DIR'), 'repos', d.getVar('FLATPAK_APP_PACKAGE'))
    shutil.copytree(src, os.path.join(d.getVar('FLATPAK_DEPLOYDIR'), 'repo'), symlinks=True)
}
do_deploy_flatpak[cleandirs] = "${FLATPAK_DEPLOYDIR}"
addtask deploy_flatpak after do_install before do_build
