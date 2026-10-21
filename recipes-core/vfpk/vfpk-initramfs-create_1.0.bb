#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Boot blobs of the vfpk guest"
DESCRIPTION = "Collects the kernel, the tiny initramfs and the squashfs root \
               filesystem of the vfpk guest into one directory for \
               vfpk-runner.sh."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit deploy nopackages flatpak-common

# Only meaningful in a vfpk-* multiconfig.
COMPATIBLE_HOST = "(aarch64|x86_64|riscv64|arm).*-linux.*"
EXCLUDE_FROM_WORLD = "1"

# Nothing to fetch: the inputs are other recipes' deploy output.
SRC_URI = ""
INHIBIT_DEFAULT_DEPS = "1"
PACKAGE_ARCH = "${MACHINE_ARCH}"

python () {
    if d.getVar('DISTRO') != 'vfpk':
        raise bb.parse.SkipRecipe('only built in a vfpk-* multiconfig (DISTRO = "vfpk")')
}

do_deploy[depends] += " \
    vfpk-tiny-initramfs-image:do_image_complete \
    vfpk-rootfs-image:do_image_complete \
    virtual/kernel:do_deploy \
"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_deploy() {
    dest=${DEPLOYDIR}/vfpk/${FLATPAK_ARCH}
    install -d $dest
    install -m 0644 ${DEPLOY_DIR_IMAGE}/${VFPK_KERNEL_IMAGETYPE} $dest/${VFPK_KERNEL_IMAGETYPE}
    install -m 0644 ${DEPLOY_DIR_IMAGE}/vfpk-tiny-initramfs-image-${MACHINE}.cpio.gz $dest/initramfs.cpio.gz
    install -m 0644 ${DEPLOY_DIR_IMAGE}/vfpk-rootfs-image-${MACHINE}.squashfs-zst $dest/rootfs.img
}
addtask deploy after do_install before do_build
