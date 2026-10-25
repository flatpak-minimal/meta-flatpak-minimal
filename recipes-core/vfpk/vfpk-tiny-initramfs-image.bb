#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Tiny initramfs of the vfpk guest"
DESCRIPTION = "busybox and vfpk-preinit, which mounts the guest root \
               filesystem and switches to it."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit image

# PACKAGE_INSTALL, not IMAGE_INSTALL: whatever a product appends to
# IMAGE_INSTALL in local.conf must not land in the guest.
PACKAGE_INSTALL = "busybox vfpk-preinit"
IMAGE_FEATURES = ""
# The guest boots under vfpk-runner, not as a MACHINE image: no BSP classes.
IMAGE_CLASSES = ""
IMAGE_LINGUAS = ""
IMAGE_FSTYPES = "cpio.gz"
PACKAGE_EXCLUDE = "kernel-image-*"
IMAGE_NAME_SUFFIX = ""

ROOTFS_POSTPROCESS_COMMAND += "vfpk_initramfs_dirs"

vfpk_initramfs_dirs() {
    install -d ${IMAGE_ROOTFS}/proc ${IMAGE_ROOTFS}/sys ${IMAGE_ROOTFS}/dev ${IMAGE_ROOTFS}/mnt
    # The kernel opens /dev/console before devtmpfs is mounted.
    mknod -m 622 ${IMAGE_ROOTFS}/dev/console c 5 1
}
