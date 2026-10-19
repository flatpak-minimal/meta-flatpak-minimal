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
