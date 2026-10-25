#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Settings shared by the vfpk build-time flatpak install: the per-architecture
# guest table and the deploy mode of the seeded installation.
#
# vfpk boots a QEMU guest of the target architecture that runs the target's
# own flatpak, so every TARGET_ARCH it supports needs a multiconfig, a QEMU
# machine and a kernel image name. The table below is the single place that
# maps them; conf/multiconfig/vfpk-*.conf must agree with it.

# TARGET_ARCH: flatpak arch, multiconfig, guest MACHINE, guest kernel image.
# The flatpak arch is what flatpak_get_arch() reports on the target, which is
# what refs are named after (arm, not aarch64, for 32-bit arm).
VFPK_ARCH_TABLE = "\
    aarch64:aarch64:vfpk-aarch64:qemuarm64:Image \
    x86_64:x86_64:vfpk-x86-64:qemux86-64:bzImage \
    riscv64:riscv64:vfpk-riscv64:qemuriscv64:Image \
    arm:arm:vfpk-arm:qemuarm:zImage \
"

def vfpk_arch_field(d, index):
    target_arch = d.getVar('TARGET_ARCH')
    for entry in (d.getVar('VFPK_ARCH_TABLE') or '').split():
        fields = entry.split(':')
        if len(fields) == 5 and fields[0] == target_arch:
            return fields[index]
    return ''

FLATPAK_ARCH = "${@vfpk_arch_field(d, 1)}"
VFPK_MULTICONFIG = "${@vfpk_arch_field(d, 2)}"
VFPK_MACHINE = "${@vfpk_arch_field(d, 3)}"
VFPK_KERNEL_IMAGETYPE = "${@vfpk_arch_field(d, 4)}"

# Each multiconfig has its own TMPDIR; the guest blobs land under its deploy
# directory.
VFPK_TMPDIR = "${TOPDIR}/tmp-${VFPK_MULTICONFIG}"
VFPK_BLOB_DIR = "${VFPK_TMPDIR}/deploy/images/${VFPK_MACHINE}/vfpk/${FLATPAK_ARCH}"

# flatpak-bundle packages install their content here; flatpak-cross-install
# collects it and removes it from the image.
FLATPAK_BUNDLES_DIR = "${datadir}/flatpak-bundles"

# Where producers deploy their refs (flatpak-deploy) and flatpak-repo-index
# publishes them. Refs land in refs/${FLATPAK_DEPLOY_ARCH}/<pn>/.
FLATPAK_DEPLOY_DIR ??= "${DEPLOY_DIR}/flatpak"
FLATPAK_DEPLOY_ARCH ??= "${PACKAGE_ARCH}"

# The multiconfig that builds runtimes with the baseline CPU tune of their
# flatpak arch rather than MACHINE's (conf/multiconfig/vfpk-*-generic.conf),
# for flatpak-bundle's FLATPAK_IMAGE_GENERIC. It deploys into this
# configuration's FLATPAK_DEPLOY_DIR, under refs/<multiconfig>/.
FLATPAK_GENERIC_MULTICONFIG = "${@'%s-generic' % d.getVar('VFPK_MULTICONFIG') if d.getVar('VFPK_MULTICONFIG') else ''}"

# The layer's base runtime and SDK (recipes-graphics/flatpak-platform). Their
# branch is the oe-core release whose ABI they carry.
FLATPAK_PLATFORM_ID = "org.flatpak_minimal.Platform"
FLATPAK_PLATFORM_SDK_ID = "org.flatpak_minimal.Sdk"
FLATPAK_PLATFORM_BRANCH ??= "${@(d.getVar('LAYERSERIES_CORENAMES') or 'unknown').split()[0]}"
FLATPAK_PLATFORM_PACKAGE = "flatpak-platform-runtime"

# Free space every ostree repository the layer writes must leave on its
# filesystem. ostree's default is 3% of the filesystem, which on a large
# shared build disk refuses writes with plenty of room left.
FLATPAK_REPO_MIN_FREE ??= "1GB"

# Licenses paired with an exception, as LEGACY:LICENSE:EXCEPTION. oe-core
# up to wrynose names each pair as one license, LEGACY; later releases write
# 'LICENSE WITH EXCEPTION', which wrynose cannot parse, and deprecate LEGACY.
# flatpak_license writes a pair the way the running oe-core wants it, and
# flatpak_license_names reports either spelling as LEGACY.
FLATPAK_LICENSE_PAIRS ??= "\
    GPL-2.0-with-GCC-exception:GPL-2.0-or-later:GCC-exception-2.0 \
    GPL-3.0-with-GCC-exception:GPL-3.0-or-later:GCC-exception-3.1 \
    Apache-2.0-with-LLVM-exception:Apache-2.0:LLVM-exception \
"

def flatpak_license(d, names):
    """A LICENSE value naming every license in NAMES, space-separated and
    spelled as wrynose spells them (PD, GPL-3.0-with-GCC-exception), in the
    syntax this oe-core parses without a warning:

      LICENSE = "${@flatpak_license(d, 'MIT PD GPL-3.0-with-GCC-exception')}"

    gives 'MIT & PD & GPL-3.0-with-GCC-exception' up to wrynose and, where
    oe-core parses SPDX expressions (oe.spdx_license),
    'MIT AND LicenseRef-PD AND GPL-3.0-or-later WITH GCC-exception-3.1':
    pairs from FLATPAK_LICENSE_PAIRS, then oe-core's own conversion.
    """
    import importlib.util
    names = (names or '').split()
    if importlib.util.find_spec('oe.spdx_license') is None:
        return ' & '.join(names)
    import oe.license
    pairs = {}
    for entry in (d.getVar('FLATPAK_LICENSE_PAIRS') or '').split():
        legacy, lic, exception = entry.split(':')
        pairs[legacy] = '%s WITH %s' % (lic, exception)
    return oe.license.convert_legacy_license_to_spdx(d, ' & '.join(pairs.get(n, n) for n in names))

def flatpak_license_names(d, expression):
    """The license units in a LICENSE expression, without its operators,
    spelled the way every supported oe-core release can declare them.

    LICENSE arrives here from recipes in this layer and from pkgdata for
    every package installed in an image, which carries whatever the recipe
    that built it wrote. Releases spell the same license differently:

      wrynose                       later (SPDX expressions)
      PD                            LicenseRef-PD
      GPL-3.0-with-GCC-exception    GPL-3.0-or-later WITH GCC-exception-3.1

    Units are compared in the left column, which wrynose parses: the
    LicenseRef- prefix goes, and a pair in FLATPAK_LICENSE_PAIRS becomes
    its legacy name, so a deployed list and a LICENSE from either release
    agree. A pair not listed stays 'LICENSE WITH EXCEPTION';
    an exception is not a license on its own, so it is never split off.

    AND and OR are dropped, along with '&', '|' and parentheses.
    """
    import re
    pairs = {}
    for entry in (d.getVar('FLATPAK_LICENSE_PAIRS') or '').split():
        legacy, lic, exception = entry.split(':')
        pairs['%s WITH %s' % (lic, exception)] = legacy

    units = []
    exception_next = False
    for token in re.findall(r'[A-Za-z0-9.+_-]+', expression or ''):
        if token in ('AND', 'OR'):
            exception_next = False
        elif token == 'WITH':
            exception_next = True
        elif exception_next and units:
            units[-1] = '%s WITH %s' % (units[-1], token)
            exception_next = False
        else:
            units.append(token[len('LicenseRef-'):] if token.startswith('LicenseRef-') else token)
    return set(pairs.get(unit, unit) for unit in units)


# Where the installation built in the guest ends up:
#   rootfs    - unpacked into ${IMAGE_ROOTFS}/var/lib/flatpak. Only valid when
#               the rootfs is writable at runtime.
#   partition - an ext4 image in DEPLOY_DIR_IMAGE that wic places as the
#               partition mounted at /var/lib/flatpak.
#   seed      - a tar in the rootfs that a first-boot service unpacks into
#               the writable /var/lib/flatpak.
# A read-only rootfs cannot hold an installation that 'flatpak update' can
# write to, so it defaults to partition.
FLATPAK_DEPLOY_MODES = "rootfs partition seed"
FLATPAK_DEPLOY_MODE ??= "${@bb.utils.contains('IMAGE_FEATURES', 'read-only-rootfs', 'partition', 'rootfs', d)}"

python () {
    if not bb.data.inherits_class('image', d):
        return

    mode = d.getVar('FLATPAK_DEPLOY_MODE')
    modes = (d.getVar('FLATPAK_DEPLOY_MODES') or '').split()
    if mode not in modes:
        bb.fatal("FLATPAK_DEPLOY_MODE is '%s'; it must be one of: %s" % (mode, ' '.join(modes)))
    if mode == 'rootfs' and bb.utils.contains('IMAGE_FEATURES', 'read-only-rootfs', True, False, d):
        bb.fatal("FLATPAK_DEPLOY_MODE = 'rootfs' cannot be used with the read-only-rootfs image "
                 "feature: flatpak cannot update an installation on a read-only filesystem. "
                 "Use 'partition' or 'seed'.")
}
