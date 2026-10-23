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
# repository deployed to ${DEPLOY_DIR}/flatpak/refs/<package arch>/${PN}/repo
# (flatpak-deploy.bbclass), with the licenses of every package in it listed
# in licenses beside it. A flatpak-bundle recipe with FLATPAK_IMAGE packages
# it for flatpak-cross-install, and checks its LICENSE against that list.
#
# flatpak links /lib, /bin and friends to /usr inside the sandbox, so the
# image needs a merged /usr (the usrmerge distro feature). Apps run with the
# runtime's dynamic linker and libraries, so include ldconfig, which flatpak
# runs to build the sandbox's ld.so.cache.
#
# A runtime and its SDK are two images of the same build and branch:
#
#   runtime image:  FLATPAK_RUNTIME_SDK = "org.example.Sdk"
#   SDK image:      FLATPAK_RUNTIME_ID = "org.example.Sdk"
#                   FLATPAK_RUNTIME_PLATFORM = "org.example.Platform"
#
# which become sdk= in the runtime's metadata and runtime= in the SDK's, so
# flatpak-builder builds in the SDK and runs in the runtime. The SDK image
# installs the runtime's packages plus development files and tools. An SDK
# also declares the ${FLATPAK_RUNTIME_ID}.Extension extension point at
# ${libdir}/sdk, where flatpak-builder's sdk-extensions are mounted, each in
# the subdirectory named by the last part of its ID.
#
# FLATPAK_RUNTIME_GL picks where the GL stack goes:
#
#   runtime    in the runtime, like everything else (default)
#   extension  in runtime/${FLATPAK_RUNTIME_ID}.GL.${FLATPAK_RUNTIME_GL_NAME},
#              committed beside the runtime
#
# With extension, the ${libdir} files of the packages built by
# FLATPAK_RUNTIME_GL_RECIPES (Mesa: libEGL, libGLESv2, libgbm, the gallium,
# DRI and GBM drivers) move out of the runtime, and the runtime declares the
# ${FLATPAK_RUNTIME_ID}.GL extension point at ${libdir}/GL, as Freedesktop's
# runtime does. flatpak mounts the extension for each active GL driver
# (FLATPAK_GL_DRIVERS, by default "default" and "host"), puts its lib/ on the
# linker path and merges lib/dri and lib/gbm. Another build of the same
# runtime branch can then ship its GL stack for another GPU as
# ${FLATPAK_RUNTIME_ID}.GL.<name>, chosen on the device with
# FLATPAK_GL_DRIVERS=<name>. The libraries move whole, without libglvnd, so
# a vendor stack that brings its own libEGL works the same way.

inherit image flatpak-repo flatpak-deploy

FLATPAK_RUNTIME_ID ??= ""
FLATPAK_RUNTIME_BRANCH ??= ""
FLATPAK_RUNTIME_SDK ??= ""
FLATPAK_RUNTIME_PLATFORM ??= ""
FLATPAK_RUNTIME_REF = "runtime/${FLATPAK_RUNTIME_ID}/${FLATPAK_ARCH}/${FLATPAK_RUNTIME_BRANCH}"

# A runtime is a userspace, not a bootable system.
IMAGE_FSTYPES = ""
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
KERNELDEPMODDEPEND = ""
KERNEL_DEPLOY_DEPEND = ""
# Bootloaders and firmware the machine builds with its images.
EXTRA_IMAGEDEPENDS = ""
# Nothing in a sandbox authenticates: libpam, which libcap links with PAM
# enabled, comes without its configuration and modules.
BAD_RECOMMENDATIONS += "libpam-runtime"

FLATPAK_RUNTIME_REPO = "${FLATPAK_DEPLOYDIR}/repo"

FLATPAK_RUNTIME_GL ??= "runtime"
FLATPAK_RUNTIME_GL_NAME ??= "default"
FLATPAK_RUNTIME_GL_RECIPES ??= "mesa"
# Installed packages of those recipes to leave in the runtime. The Vulkan
# ICD files name their drivers by absolute path, so they stay together.
FLATPAK_RUNTIME_GL_EXCLUDE ??= "mesa-vulkan-drivers"
# The extension's branch, which the runtime's extension point asks for.
FLATPAK_RUNTIME_GL_VERSION ??= "${FLATPAK_RUNTIME_BRANCH}"
FLATPAK_RUNTIME_GL_REF = "runtime/${FLATPAK_RUNTIME_ID}.GL.${FLATPAK_RUNTIME_GL_NAME}/${FLATPAK_ARCH}/${FLATPAK_RUNTIME_GL_VERSION}"

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
    for var in ('FLATPAK_RUNTIME_SDK', 'FLATPAK_RUNTIME_PLATFORM'):
        if d.getVar(var) and not re.fullmatch(d.getVar('FLATPAK_ID_RE'), d.getVar(var)):
            bb.fatal("%s '%s' is not a flatpak ID" % (var, d.getVar(var)))
    if d.getVar('FLATPAK_RUNTIME_SDK') and d.getVar('FLATPAK_RUNTIME_PLATFORM'):
        bb.fatal("set FLATPAK_RUNTIME_SDK on a runtime image or FLATPAK_RUNTIME_PLATFORM on an SDK image, not both")
    if d.getVar('FLATPAK_RUNTIME_PLATFORM') and d.getVar('FLATPAK_RUNTIME_GL') != 'runtime':
        bb.fatal("an SDK keeps its GL stack: FLATPAK_RUNTIME_GL must be runtime")
    if d.getVar('FLATPAK_RUNTIME_GL') not in ('runtime', 'extension'):
        bb.fatal("FLATPAK_RUNTIME_GL is '%s'; use runtime or extension" % d.getVar('FLATPAK_RUNTIME_GL'))
    # The last part of an extension ID may hold dashes (nvidia-550-54).
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*', d.getVar('FLATPAK_RUNTIME_GL_NAME') or ''):
        bb.fatal("FLATPAK_RUNTIME_GL_NAME '%s' is not a flatpak ID part" % d.getVar('FLATPAK_RUNTIME_GL_NAME'))
    if not re.fullmatch(d.getVar('FLATPAK_BRANCH_RE'), d.getVar('FLATPAK_RUNTIME_GL_VERSION') or ''):
        bb.fatal("FLATPAK_RUNTIME_GL_VERSION '%s' is not a flatpak branch" % d.getVar('FLATPAK_RUNTIME_GL_VERSION'))
}

def flatpak_runtime_packages(d):
    """pkgdata of every package installed in the image, by package name."""
    import oe.packagedata

    packages = {}
    with open(d.getVar('IMAGE_MANIFEST')) as f:
        for line in f:
            if line.strip():
                pkg = line.split()[0]
                packages[pkg] = oe.packagedata.read_pkgdatafile(
                    os.path.join(d.getVar('PKGDATA_DIR'), 'runtime-reverse', pkg))
    return packages

def flatpak_runtime_split_gl(d, files, gl_files):
    """Move the GL packages' ${libdir} files from FILES to GL_FILES/lib."""
    import json

    prefix = d.getVar('prefix')
    libdir = d.getVar('libdir')
    recipes = (d.getVar('FLATPAK_RUNTIME_GL_RECIPES') or '').split()
    exclude = (d.getVar('FLATPAK_RUNTIME_GL_EXCLUDE') or '').split()
    moved = []
    for pkg, data in sorted(flatpak_runtime_packages(d).items()):
        if data.get('PN') not in recipes or pkg in exclude:
            continue
        info = next((v for k, v in data.items() if k.startswith('FILES_INFO')), '{}')
        for path in sorted(json.loads(info)):
            if not path.startswith(libdir + '/'):
                continue
            src = os.path.join(files, path[len(prefix) + 1:])
            if not os.path.lexists(src):
                continue
            dest = os.path.join(gl_files, 'lib', path[len(libdir) + 1:])
            bb.utils.mkdirhier(os.path.dirname(dest))
            os.rename(src, dest)
            moved.append(path)
    if not moved:
        bb.fatal("FLATPAK_RUNTIME_GL = \"extension\", but no package of %s installs files in %s"
                 % (' '.join(recipes), libdir))
    return moved

def flatpak_runtime_licenses(d):
    """The license names of every package installed in the image."""
    names = set()
    for pkg, data in flatpak_runtime_packages(d).items():
        # Per-package LICENSE:<pkg> overrides the recipe's LICENSE.
        value = next((v for k, v in data.items() if k.startswith('LICENSE:')), data.get('LICENSE'))
        if not value:
            bb.fatal("no license recorded for %s, installed in the runtime" % pkg)
        names |= flatpak_license_names(value)
    return sorted(names)

python do_deploy_flatpak () {
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

    runtime_id = d.getVar('FLATPAK_RUNTIME_ID')
    ref = d.getVar('FLATPAK_RUNTIME_REF')
    # name/arch/branch, as the metadata names runtimes.
    tail = '%s/%s' % (d.getVar('FLATPAK_ARCH'), d.getVar('FLATPAK_RUNTIME_BRANCH'))
    platform = d.getVar('FLATPAK_RUNTIME_PLATFORM')
    sdk = d.getVar('FLATPAK_RUNTIME_SDK') or (runtime_id if platform else '')
    metadata = '[Runtime]\nname=%s\nruntime=%s/%s\n' % (runtime_id, platform or runtime_id, tail)
    if sdk:
        metadata += 'sdk=%s/%s\n' % (sdk, tail)
    subject = '%s %s' % (d.getVar('PN'), d.getVar('PV'))

    if platform:
        # SDK extensions (flatpak-builder sdk-extensions) mount at
        # ${libdir}/sdk/<last part of their ID>, as in Freedesktop's SDK.
        sdk_dir = d.getVar('libdir')[len(d.getVar('prefix')) + 1:] + '/sdk'
        bb.utils.mkdirhier(os.path.join(files, sdk_dir))
        metadata += ('\n[Extension %s.Extension]\n'
                     'directory=%s\n'
                     'subdirectories=true\n'
                     'no-autodownload=true\n'
                     'autodelete=false\n'
                     'version=%s\n'
                     % (runtime_id, sdk_dir, d.getVar('FLATPAK_RUNTIME_BRANCH')))

    if d.getVar('FLATPAK_RUNTIME_GL') == 'extension':
        gl_tree = os.path.join(work, 'gl')
        moved = flatpak_runtime_split_gl(d, files, os.path.join(gl_tree, 'files'))
        gl_dir = d.getVar('libdir')[len(d.getVar('prefix')) + 1:] + '/GL'
        # flatpak mounts a tmpfs here for the subdirectories; /usr is
        # read-only, so the directory has to exist.
        bb.utils.mkdirhier(os.path.join(files, gl_dir))
        gl_path = os.path.join(d.getVar('prefix'), gl_dir)
        metadata += ('\n[Environment]\n'
                     'LIBGL_DRIVERS_PATH=%s/lib/dri\n'
                     'GBM_BACKENDS_PATH=%s/lib/gbm\n'
                     '\n[Extension %s.GL]\n'
                     'version=%s\n'
                     'directory=%s\n'
                     'subdirectories=true\n'
                     'no-autodownload=true\n'
                     'autodelete=false\n'
                     'add-ld-path=lib\n'
                     'merge-dirs=lib/dri;lib/gbm\n'
                     'download-if=active-gl-driver\n'
                     'enable-if=active-gl-driver\n'
                     'autoprune-unless=active-gl-driver\n'
                     % (gl_path, gl_path, runtime_id, d.getVar('FLATPAK_RUNTIME_GL_VERSION'), gl_dir))
        gl_ref = d.getVar('FLATPAK_RUNTIME_GL_REF')
        with open(os.path.join(gl_tree, 'metadata'), 'w') as f:
            f.write('[Runtime]\nname=%s\nruntime=%s\n\n[ExtensionOf]\nref=%s\n'
                    % (gl_ref.split('/')[1], ref.split('/', 1)[1], ref))
        commit = flatpak_repo_commit(d, repo, gl_ref, gl_tree, subject)
        bb.note("Committed %s as %s (%d files)" % (gl_ref, commit, len(moved)))

    with open(os.path.join(tree, 'metadata'), 'w') as f:
        f.write(metadata)
    commit = flatpak_repo_commit(d, repo, ref, tree, subject)
    bb.note("Committed %s as %s" % (ref, commit))
    bb.utils.remove(work, recurse=True)

    with open(os.path.join(d.getVar('FLATPAK_DEPLOYDIR'), 'licenses'), 'w') as f:
        f.write(''.join(name + '\n' for name in flatpak_runtime_licenses(d)))
    # flatpak-extension-image leaves these out of extensions of the runtime.
    with open(os.path.join(d.getVar('FLATPAK_DEPLOYDIR'), 'packages'), 'w') as f:
        f.write(''.join(pkg + '\n' for pkg in sorted(flatpak_runtime_packages(d))))
}
do_deploy_flatpak[cleandirs] = "${FLATPAK_DEPLOYDIR}"
do_deploy_flatpak[vardeps] += "FLATPAK_RUNTIME_ID FLATPAK_RUNTIME_BRANCH FLATPAK_GPGID FLATPAK_RUNTIME_GL \
    FLATPAK_RUNTIME_SDK FLATPAK_RUNTIME_PLATFORM \
    FLATPAK_RUNTIME_GL_NAME FLATPAK_RUNTIME_GL_RECIPES FLATPAK_RUNTIME_GL_EXCLUDE FLATPAK_RUNTIME_GL_VERSION"
# The key's location is not content; the key ID is.
do_deploy_flatpak[vardepsexclude] += "FLATPAK_GPGHOME"
addtask deploy_flatpak after do_image before do_image_complete
