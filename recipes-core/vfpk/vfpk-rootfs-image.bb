#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Root filesystem of the vfpk guest"
DESCRIPTION = "flatpak, ostree and bubblewrap for installing flatpak refs \
               at build time, booted read-only by vfpk-runner.sh."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit image

# PACKAGE_INSTALL, not IMAGE_INSTALL: whatever a product appends to
# IMAGE_INSTALL in local.conf must not land in the guest. gnupg is what
# ostree's gpgme calls to verify signed commits and summaries.
PACKAGE_INSTALL = " \
    busybox \
    ca-certificates \
    flatpak \
    gnupg \
    ostree \
    tar \
    vfpk-init \
"
IMAGE_FEATURES = ""
# The guest boots under vfpk-runner, not as a MACHINE image: no BSP classes.
IMAGE_CLASSES = ""
IMAGE_LINGUAS = ""
IMAGE_FSTYPES = "squashfs-zst"
IMAGE_NAME_SUFFIX = ""

ROOTFS_POSTPROCESS_COMMAND += "vfpk_rootfs_tweaks"

vfpk_rootfs_tweaks() {
    install -d ${IMAGE_ROOTFS}/proc ${IMAGE_ROOTFS}/sys ${IMAGE_ROOTFS}/dev \
        ${IMAGE_ROOTFS}/run ${IMAGE_ROOTFS}/tmp ${IMAGE_ROOTFS}/mnt/input \
        ${IMAGE_ROOTFS}/var/lib/flatpak
}
