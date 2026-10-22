#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Standalone vfpk for development hosts"
DESCRIPTION = "A relocatable SDK installer with the vfpk front-end, \
               vfpk-runner.sh, the guest blobs of one architecture and the \
               QEMU and mke2fs they need, for installing and running \
               flatpaks for a target without a build tree."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"
SECTION = "devel"

LICENSE = "MIT"

# Built in the vfpk-<arch> multiconfig, where the blobs are, for one arch:
#   bitbake mc:vfpk-aarch64:vfpk-tarball
# The installer lands in tmp-vfpk-aarch64/deploy/sdk/.
python () {
    if d.getVar('DISTRO') != 'vfpk':
        raise bb.parse.SkipRecipe('only built in a vfpk-* multiconfig (DISTRO = "vfpk")')
}

# TARGET_ARCH is "none" below; the machine's own arch is the guest's.
VFPK_TARBALL_ARCH = "${TUNE_ARCH}"

TOOLCHAIN_TARGET_TASK = ""
TOOLCHAIN_HOST_TASK = " \
    nativesdk-sdk-provides-dummy \
    nativesdk-e2fsprogs \
    nativesdk-qemu-system-${@d.getVar("VFPK_TARBALL_ARCH").replace("_", "-")} \
"
TOOLCHAIN_OUTPUTNAME = "vfpk-standalone-${SDK_ARCH}-${VFPK_TARBALL_ARCH}"
SDK_TITLE = "vfpk (${VFPK_TARBALL_ARCH})"

MULTIMACH_TARGET_SYS = "${SDK_ARCH}-nativesdk${SDK_VENDOR}-${SDK_OS}"
PACKAGE_ARCH = "${SDK_ARCH}-${SDKPKGSUFFIX}"
PACKAGE_ARCHS = ""
TARGET_ARCH = "none"
TARGET_OS = "none"
SDK_PACKAGE_ARCHS += "vfpk-dummy-${SDKPKGSUFFIX}"

RDEPENDS = "${TOOLCHAIN_HOST_TASK}"
EXCLUDE_FROM_WORLD = "1"

inherit populate_sdk
inherit toolchain-scripts-base
inherit nopackages

deltask install
deltask populate_sysroot

do_populate_sdk[stamp-extra-info] = "${PACKAGE_ARCH}"
REAL_MULTIMACH_TARGET_SYS = "none"
TOOLCHAIN_NEED_CONFIGSITE_CACHE = ""
# QEMU and mke2fs need no locales.
SDKIMAGE_LINGUAS = ""
INHIBIT_DEFAULT_DEPS = "1"

VFPK_FILES := "${THISDIR}/files"
VFPK_TARBALL_BLOBS = "${DEPLOY_DIR_IMAGE}/vfpk/${VFPK_TARBALL_ARCH}"

do_populate_sdk[depends] += "vfpk-initramfs-create:do_deploy"
do_populate_sdk[file-checksums] += " \
    ${VFPK_FILES}/vfpk.sh:True \
    ${VFPK_FILES}/vfpk-runner.sh:True \
"

# Everything has to be in place before archive_sdk, which runs right after
# create_sdk_files.
create_sdk_files:append () {
    rm -f ${SDK_OUTPUT}/${SDKPATH}/site-config-*
    rm -f ${SDK_OUTPUT}/${SDKPATH}/environment-setup-*
    rm -f ${SDK_OUTPUT}/${SDKPATH}/version-*

    install -m 0755 ${VFPK_FILES}/vfpk.sh ${SDK_OUTPUT}/${SDKPATH}/vfpk
    install -m 0755 ${VFPK_FILES}/vfpk-runner.sh ${SDK_OUTPUT}/${SDKPATH}/vfpk-runner.sh
    install -d ${SDK_OUTPUT}/${SDKPATH}/blobs/${VFPK_TARBALL_ARCH}
    for blob in ${VFPK_TARBALL_BLOBS}/*; do
        install -m 0644 $blob ${SDK_OUTPUT}/${SDKPATH}/blobs/${VFPK_TARBALL_ARCH}/
    done

    # The guest boots with -kernel; UEFI firmware for every arch QEMU
    # knows is 300 MB of nothing.
    rm -f ${SDK_OUTPUT}/${SDKPATHNATIVE}${datadir}/qemu/edk2-*

    # vfpk finds its tools on its own; the script only puts it on PATH. The
    # installer reads OECORE_NATIVE_SYSROOT from it to find what to relocate.
    script=${SDK_OUTPUT}/${SDKPATH}/environment-setup-${SDK_SYS}
    echo 'export PATH="${SDKPATH}:$PATH"' > $script
    echo 'OECORE_NATIVE_SYSROOT="${SDKPATHNATIVE}"' >> $script
    echo 'unset OECORE_NATIVE_SYSROOT' >> $script
    toolchain_create_sdk_version ${SDK_OUTPUT}/${SDKPATH}/version-${SDK_SYS}
}
create_sdk_files[vardepsexclude] += "VFPK_FILES VFPK_TARBALL_BLOBS"
