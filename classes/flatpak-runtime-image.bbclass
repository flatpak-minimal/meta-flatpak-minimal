#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Turn an image into a flatpak runtime.
#
#   inherit flatpak-runtime-image
#   FLATPAK_RUNTIME_ID = "org.example.Platform"
#   FLATPAK_RUNTIME_BRANCH = "1.0"
#   IMAGE_INSTALL = "..."
#
# The image's /usr becomes the runtime's files/ (mounted at /usr in the
# sandbox) and its /etc becomes files/etc, which flatpak exposes as /etc.
# The result is committed as runtime/ID/ARCH/BRANCH into an ostree archive
# repository deployed as ${IMAGE_LINK_NAME}.flatpakrepo. A flatpak-bundle
# recipe with FLATPAK_IMAGE packages it for flatpak-cross-install.
#
# flatpak links /lib, /bin and friends to /usr inside the sandbox, so the
# image needs a merged /usr (the usrmerge distro feature). Apps run with the
# runtime's dynamic linker and libraries, so include ldconfig, which flatpak
# runs to build the sandbox's ld.so.cache.

inherit image flatpak-repo

FLATPAK_RUNTIME_ID ??= ""
FLATPAK_RUNTIME_BRANCH ??= ""
FLATPAK_RUNTIME_REF = "runtime/${FLATPAK_RUNTIME_ID}/${FLATPAK_ARCH}/${FLATPAK_RUNTIME_BRANCH}"

# A runtime is a userspace, not a bootable system.
IMAGE_FSTYPES = ""
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
KERNELDEPMODDEPEND = ""

FLATPAK_RUNTIME_REPO = "${IMGDEPLOYDIR}/${IMAGE_NAME}.flatpakrepo"

python () {
    import re

    if not d.getVar('FLATPAK_ARCH'):
        raise bb.parse.SkipRecipe("flatpak has no arch for TARGET_ARCH %s" % d.getVar('TARGET_ARCH'))
    if not re.fullmatch(d.getVar('FLATPAK_ID_RE'), d.getVar('FLATPAK_RUNTIME_ID') or ''):
        bb.fatal("FLATPAK_RUNTIME_ID '%s' is not a flatpak ID (reverse DNS, three parts or more)"
                 % d.getVar('FLATPAK_RUNTIME_ID'))
    if not re.fullmatch(d.getVar('FLATPAK_BRANCH_RE'), d.getVar('FLATPAK_RUNTIME_BRANCH') or ''):
        bb.fatal("FLATPAK_RUNTIME_BRANCH '%s' is not a flatpak branch" % d.getVar('FLATPAK_RUNTIME_BRANCH'))
    if not bb.utils.contains('DISTRO_FEATURES', 'usrmerge', True, False, d):
        raise bb.parse.SkipRecipe("a flatpak runtime needs the usrmerge distro feature")
}

python do_flatpak_runtime () {
    import shutil
    import subprocess

    rootfs = d.getVar('IMAGE_ROOTFS')
    work = os.path.join(d.getVar('WORKDIR'), 'flatpak-runtime')
    tree = os.path.join(work, 'tree')
    repo = d.getVar('FLATPAK_RUNTIME_REPO')
    bb.utils.remove(work, recurse=True)
    bb.utils.remove(repo, recurse=True)
    bb.utils.mkdirhier(tree)

    usr = rootfs + d.getVar('prefix')
    etc = rootfs + d.getVar('sysconfdir')
    if os.path.lexists(os.path.join(usr, 'etc')):
        bb.fatal("%s/etc exists; it would collide with the runtime's /etc" % d.getVar('prefix'))
    # Hardlinks: the commit only reads the tree, and the rootfs is large.
    for src, dest in ((usr, os.path.join(tree, 'files')), (etc, os.path.join(tree, 'files', 'etc'))):
        subprocess.run(['cp', '-al', src, dest], check=True)

    # flatpak builds a linker cache per app with the runtime's bin/ldconfig;
    # without one it falls back to LD_LIBRARY_PATH=/app/lib and ignores the
    # app's /app/etc/ld.so.conf.
    files = os.path.join(tree, 'files')
    ldconfig = os.path.join(files, 'bin', 'ldconfig')
    if not os.path.lexists(ldconfig):
        if not os.path.isfile(os.path.join(files, 'sbin', 'ldconfig')):
            bb.fatal("the runtime has no ldconfig; add ldconfig to IMAGE_INSTALL")
        # Relative: flatpak resolves it beneath the runtime.
        os.symlink('../sbin/ldconfig', ldconfig)

    # flatpak writes its own ld.so.conf (app, /app/lib and extension paths)
    # only for a runtime whose ld.so.conf is empty. Write those entries here,
    # ahead of the image's own, which flatpak would otherwise lose. The tree
    # hardlinks the rootfs, so replace the file rather than write through it.
    conf = os.path.join(files, 'etc', 'ld.so.conf')
    image_conf = ''
    if os.path.isfile(conf):
        with open(conf) as f:
            image_conf = f.read()
        os.unlink(conf)
    with open(conf, 'w') as f:
        f.write('include /run/flatpak/ld.so.conf.d/app-*.conf\n'
                'include /app/etc/ld.so.conf\n'
                '/app/lib\n'
                'include /run/flatpak/ld.so.conf.d/runtime-*.conf\n' + image_conf)

    ref = d.getVar('FLATPAK_RUNTIME_REF')
    with open(os.path.join(tree, 'metadata'), 'w') as f:
        f.write('[Runtime]\nname=%s\nruntime=%s\n'
                % (d.getVar('FLATPAK_RUNTIME_ID'), ref.split('/', 1)[1]))

    commit = flatpak_repo_commit(d, repo, ref, tree, '%s %s' % (d.getVar('PN'), d.getVar('PV')))
    bb.note("Committed %s as %s" % (ref, commit))
    bb.utils.remove(work, recurse=True)

    link = d.getVar('IMAGE_LINK_NAME')
    if link:
        path = os.path.join(d.getVar('IMGDEPLOYDIR'), link + '.flatpakrepo')
        if os.path.lexists(path):
            os.unlink(path)
        os.symlink(os.path.basename(repo), path)
}
do_flatpak_runtime[vardeps] += "FLATPAK_RUNTIME_ID FLATPAK_RUNTIME_BRANCH FLATPAK_GPGID"
# The key's location is not content; the key ID is.
do_flatpak_runtime[vardepsexclude] += "FLATPAK_GPGHOME"
addtask flatpak_runtime after do_image before do_image_complete
