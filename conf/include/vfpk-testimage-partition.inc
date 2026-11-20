#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# vfpk-testimage.inc with the test content on a data partition that
# systemd-repart grows on first boot. Boots a GPT wic image, made 1 GiB
# larger than its partitions so repart has room to grow into. qemux86-64
# only, for its BIOS GPT layout. For a local run add to local.conf:
#
#   BBMULTICONFIG = "vfpk-x86-64"
#   require conf/include/vfpk-testimage-partition.inc
#
# then: bitbake flatpak-minimal-image -c testimage
#
# Not for products, for the reasons in vfpk-testimage.inc.

require conf/include/vfpk-testimage.inc

FLATPAK_DEPLOY_MODE:pn-flatpak-minimal-image = "partition"
FLATPAK_DATA_GROW:pn-flatpak-minimal-image = "1"
# The same in every build, for vfpk-testimage-update.inc.
FLATPAK_DATA_SIZE:pn-flatpak-minimal-image = "1536"
PACKAGECONFIG:append:pn-systemd = " repart openssl"

IMAGE_FSTYPES:append:pn-flatpak-minimal-image = " wic"
QB_DEFAULT_FSTYPE:pn-flatpak-minimal-image = "wic"
WKS_FILE:pn-flatpak-minimal-image = "flatpak-data.wks.in"
FLATPAK_DATA_BASE_WKS:pn-flatpak-minimal-image = "directdisk-gpt.wks"

# Free space after the last partition. runqemu boots the image in snapshot
# mode, so the guest sees the larger disk and the build output is unchanged.
vfpk_test_grow_disk () {
	truncate -s +1G ${IMGDEPLOYDIR}/${IMAGE_NAME}.wic
}
do_image_wic[postfuncs] += "${@'vfpk_test_grow_disk' if d.getVar('PN') == 'flatpak-minimal-image' else ''}"
