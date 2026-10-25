#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Turn an image into a flatpak extension of a runtime built by
# flatpak-runtime-image.
#
#   inherit flatpak-extension-image
#   FLATPAK_EXTENSION_ID = "org.example.Platform.Foo"
#   FLATPAK_EXTENSION_BRANCH = "1.0"
#   FLATPAK_EXTENSION_BASE = "example-platform-runtime-image"
#   FLATPAK_EXTENSION_OF = "runtime/org.example.Platform/${FLATPAK_ARCH}/1"
#   FLATPAK_EXTENSION_PACKAGES = "foo"
#
# The image installs FLATPAK_EXTENSION_PACKAGES with its dependencies.
# Packages the base runtime image has stay out; every other package goes into the
# extension, ${prefix}/X as X and ${sysconfdir}/X as etc/X, and are
# committed as runtime/ID/ARCH/BRANCH. Both images come from the same build,
# so the extension's binaries match the runtime's libraries.
#
# flatpak mounts the extension where an extension point names it: an app's
# metadata (/app/DIR) or a runtime's (/usr/DIR). Paths the extension's
# programs were built with (${bindir}, ${datadir}) are not valid there, so
# whatever refers to them has to translate, as flatpak-app does for symlinks
# with FLATPAK_APP_EXTENSION_PATHS.
#
# FLATPAK_EXTENSION_EXCLUDE_RECIPES leaves the packages of the listed recipes
# out too, though FLATPAK_EXTENSION_PACKAGES depends on them: another
# extension carries them.
#
# FLATPAK_EXTENSION_MOUNT, the directory the extension is mounted at, adds an
# enable.sh that puts its bin, include, lib and pkgconfig directories on the
# usual search paths, as Freedesktop's SDK extensions do;
# FLATPAK_EXTENSION_ENABLE_VARS adds NAME=PATH pairs exported as the mount
# directory joined with PATH.

inherit image flatpak-repo flatpak-deploy

# Product configuration can append boot and development packages to
# IMAGE_INSTALL globally. Keep the sandbox's explicit package set separate,
# while preserving requested features (SDK dev-pkgs). A sandbox has no
# first boot on which to run deferred postinsts; do not install run-postinsts
# or its shell and base-files dependencies through the image bootstrap.
FLATPAK_EXTENSION_PACKAGES ??= ""
PACKAGE_INSTALL = "${FLATPAK_EXTENSION_PACKAGES} ${FEATURE_INSTALL}"

FLATPAK_EXTENSION_ID ??= ""
FLATPAK_EXTENSION_BRANCH ??= ""
FLATPAK_EXTENSION_BASE ??= ""
FLATPAK_EXTENSION_OF ??= ""
FLATPAK_EXTENSION_EXCLUDE_RECIPES ??= ""
FLATPAK_EXTENSION_MOUNT ??= ""
FLATPAK_EXTENSION_ENABLE_VARS ??= ""
FLATPAK_EXTENSION_REF = "runtime/${FLATPAK_EXTENSION_ID}/${FLATPAK_ARCH}/${FLATPAK_EXTENSION_BRANCH}"
# What flatpak-runtime-image deploys for the base in this configuration.
FLATPAK_EXTENSION_BASE_PACKAGES = "${FLATPAK_DEPLOY_REFS_DIR}/${FLATPAK_DEPLOY_ARCH}/${FLATPAK_EXTENSION_BASE}/packages"

IMAGE_FSTYPES = ""
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
KERNELDEPMODDEPEND = ""
KERNEL_DEPLOY_DEPEND = ""
EXTRA_IMAGEDEPENDS = ""
# Add what FLATPAK_EXTENSION_PACKAGES needs to the base and nothing else.
# Recommendations pull in packages the base left out on purpose (an SDK's
# -dev packages come without their dependencies), so list wanted ones.
NO_RECOMMENDATIONS = "1"

python () {
    import re

    if not d.getVar('FLATPAK_ARCH'):
        raise bb.parse.SkipRecipe("flatpak has no arch for TARGET_ARCH %s" % d.getVar('TARGET_ARCH'))
    if not bb.utils.contains('DISTRO_FEATURES', 'usrmerge', True, False, d):
        raise bb.parse.SkipRecipe("a flatpak extension needs the usrmerge distro feature")
    if not re.fullmatch(d.getVar('FLATPAK_ID_RE'), d.getVar('FLATPAK_EXTENSION_ID') or ''):
        bb.fatal("FLATPAK_EXTENSION_ID '%s' is not a flatpak ID" % d.getVar('FLATPAK_EXTENSION_ID'))
    if not re.fullmatch(d.getVar('FLATPAK_BRANCH_RE'), d.getVar('FLATPAK_EXTENSION_BRANCH') or ''):
        bb.fatal("FLATPAK_EXTENSION_BRANCH '%s' is not a flatpak branch" % d.getVar('FLATPAK_EXTENSION_BRANCH'))
    if not d.getVar('FLATPAK_EXTENSION_BASE'):
        bb.fatal("FLATPAK_EXTENSION_BASE must name the flatpak-runtime-image the extension adds to")
    of = d.getVar('FLATPAK_EXTENSION_OF')
    if of and not re.fullmatch(r'runtime/[A-Za-z0-9._-]+/[A-Za-z0-9_]+/[A-Za-z0-9._-]+', of):
        bb.fatal("FLATPAK_EXTENSION_OF '%s' is not a runtime ref" % of)
    mount = d.getVar('FLATPAK_EXTENSION_MOUNT')
    if mount and (not mount.startswith('/') or '..' in mount.split('/')):
        bb.fatal("FLATPAK_EXTENSION_MOUNT '%s' is not an absolute path" % mount)
    for pair in (d.getVar('FLATPAK_EXTENSION_ENABLE_VARS') or '').split():
        name, sep, path = pair.partition('=')
        if not mount:
            bb.fatal("FLATPAK_EXTENSION_ENABLE_VARS needs FLATPAK_EXTENSION_MOUNT")
        if not sep or not re.fullmatch(r'[A-Z_][A-Z0-9_]*', name) or path.startswith('/') or \
                '..' in path.split('/') or not re.fullmatch(r'[A-Za-z0-9._/+-]*', path):
            bb.fatal("FLATPAK_EXTENSION_ENABLE_VARS: '%s' is not NAME=relative/path" % pair)
    d.appendVarFlag('do_deploy_flatpak', 'depends', ' %s:do_deploy_flatpak' % d.getVar('FLATPAK_EXTENSION_BASE'))
}

def flatpak_extension_packages(d):
    """pkgdata of the installed packages the base runtime does not have,
    without those of FLATPAK_EXTENSION_EXCLUDE_RECIPES."""
    import oe.packagedata

    path = d.getVar('FLATPAK_EXTENSION_BASE_PACKAGES')
    if not os.path.isfile(path):
        bb.fatal("%s deployed no package list at %s" % (d.getVar('FLATPAK_EXTENSION_BASE'), path))
    with open(path) as f:
        base = set(f.read().split())

    recipes = (d.getVar('FLATPAK_EXTENSION_EXCLUDE_RECIPES') or '').split()
    packages = {}
    with open(d.getVar('IMAGE_MANIFEST')) as f:
        for line in f:
            if line.strip() and line.split()[0] not in base:
                pkg = line.split()[0]
                data = oe.packagedata.read_pkgdatafile(
                    os.path.join(d.getVar('PKGDATA_DIR'), 'runtime-reverse', pkg))
                if data.get('PN') not in recipes:
                    packages[pkg] = data
    if not packages:
        bb.fatal("every package of the image is in %s; the extension would be empty"
                 % d.getVar('FLATPAK_EXTENSION_BASE'))
    return packages

python do_deploy_flatpak () {
    import json
    import shutil

    rootfs = d.getVar('IMAGE_ROOTFS')
    prefix = d.getVar('prefix')
    sysconfdir = d.getVar('sysconfdir')
    work = os.path.join(d.getVar('WORKDIR'), 'flatpak-extension')
    files = os.path.join(work, 'tree', 'files')
    repo = os.path.join(d.getVar('FLATPAK_DEPLOYDIR'), 'repo')
    bb.utils.remove(work, recurse=True)
    bb.utils.mkdirhier(files)

    packages = flatpak_extension_packages(d)
    count = 0
    for pkg, data in sorted(packages.items()):
        info = next((v for k, v in data.items() if k.startswith('FILES_INFO')), '{}')
        for path in sorted(json.loads(info)):
            if path.startswith(prefix + '/'):
                rel = path[len(prefix) + 1:]
            elif path.startswith(sysconfdir + '/'):
                rel = 'etc/' + path[len(sysconfdir) + 1:]
            else:
                bb.fatal("%s installs %s, outside %s and %s; an extension cannot hold it"
                         % (pkg, path, prefix, sysconfdir))
            src = rootfs + path
            if not os.path.lexists(src):
                continue
            dest = os.path.join(files, rel)
            bb.utils.mkdirhier(os.path.dirname(dest))
            if os.path.islink(src) or not os.path.isfile(src):
                shutil.copy2(src, dest, follow_symlinks=False)
            else:
                # Hardlink: the commit only reads the tree.
                os.link(src, dest)
            count += 1

    mount = d.getVar('FLATPAK_EXTENSION_MOUNT')
    if mount:
        enable = ['export PATH=%s/bin${PATH:+:$PATH}' % mount,
                  'export CPATH=%s/include${CPATH:+:$CPATH}' % mount,
                  'export LIBRARY_PATH=%s/lib${LIBRARY_PATH:+:$LIBRARY_PATH}' % mount,
                  'export LD_LIBRARY_PATH=%s/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}' % mount,
                  'export PKG_CONFIG_PATH=%s/lib/pkgconfig:%s/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}'
                  % (mount, mount)]
        for pair in (d.getVar('FLATPAK_EXTENSION_ENABLE_VARS') or '').split():
            name, _, path = pair.partition('=')
            enable.append('export %s=%s' % (name, os.path.join(mount, path)))
        with open(os.path.join(files, 'enable.sh'), 'w') as f:
            f.write('\n'.join(enable) + '\n')

    ext_id = d.getVar('FLATPAK_EXTENSION_ID')
    ref = d.getVar('FLATPAK_EXTENSION_REF')
    metadata = '[Runtime]\nname=%s\n' % ext_id
    of = d.getVar('FLATPAK_EXTENSION_OF')
    if of:
        metadata += 'runtime=%s\n\n[ExtensionOf]\nref=%s\n' % (of.split('/', 1)[1], of)
    with open(os.path.join(work, 'tree', 'metadata'), 'w') as f:
        f.write(metadata)

    bb.utils.remove(repo, recurse=True)
    commit = flatpak_repo_commit(d, repo, ref, os.path.join(work, 'tree'), '%s %s' % (d.getVar('PN'), d.getVar('PV')))
    bb.note("Committed %s as %s (%d files from %s)" % (ref, commit, count, ' '.join(sorted(packages))))
    bb.utils.remove(work, recurse=True)

    names = set()
    for pkg, data in packages.items():
        value = next((v for k, v in data.items() if k.startswith('LICENSE:')), data.get('LICENSE'))
        if not value:
            bb.fatal("no license recorded for %s, installed in the extension" % pkg)
        names |= flatpak_license_names(d, value)
    with open(os.path.join(d.getVar('FLATPAK_DEPLOYDIR'), 'licenses'), 'w') as f:
        f.write(''.join(name + '\n' for name in sorted(names)))
}
do_deploy_flatpak[cleandirs] = "${FLATPAK_DEPLOYDIR}"
do_deploy_flatpak[vardeps] += "FLATPAK_EXTENSION_ID FLATPAK_EXTENSION_BRANCH FLATPAK_EXTENSION_BASE \
    FLATPAK_EXTENSION_OF FLATPAK_EXTENSION_EXCLUDE_RECIPES FLATPAK_EXTENSION_MOUNT FLATPAK_EXTENSION_ENABLE_VARS FLATPAK_GPGID"
do_deploy_flatpak[vardepsexclude] += "FLATPAK_GPGHOME FLATPAK_EXTENSION_BASE_PACKAGES"
addtask deploy_flatpak after do_image before do_image_complete
