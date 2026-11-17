#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# An OS update that turns on FLATPAK_DATA_DIRS: vfpk-testimage-partition.inc
# with /var/lib/flatpak and /home on the partition, booted with the data
# partition of an earlier build without it. First build and keep that
# partition:
#
#   require conf/include/vfpk-testimage-partition.inc
#   bitbake flatpak-minimal-image
#   cp -L tmp/deploy/images/qemux86-64/flatpak-minimal-image-qemux86-64.rootfs.vfpk-data.ext4 \
#       vfpk-old-data.ext4
#
# then require this file instead, and: bitbake flatpak-minimal-image -c testimage
#
# Not for products, for the reasons in vfpk-testimage.inc.

require conf/include/vfpk-testimage-partition.inc

FLATPAK_DATA_DIRS:pn-flatpak-minimal-image = "${localstatedir}/lib/flatpak /home"
# A home for the migration to restore.
IMAGE_CLASSES += "extrausers"
EXTRA_USERS_PARAMS:pn-flatpak-minimal-image = "useradd -m -u 1100 -s /bin/sh vfpktest;"
VFPK_TEST_OLD_DATA ?= "${TOPDIR}/vfpk-old-data.ext4"

# Write the old data partition over the new one in the .wic.
python vfpk_test_old_data () {
    import struct, uuid
    old = d.getVar('VFPK_TEST_OLD_DATA')
    if not os.path.exists(old):
        bb.fatal("%s is missing; see vfpk-testimage-update.inc" % old)
    ptype = uuid.UUID(d.getVar('FLATPAK_DATA_PART_TYPE')).bytes_le
    wic = os.path.join(d.getVar('IMGDEPLOYDIR'), d.getVar('IMAGE_NAME') + '.wic')
    with open(wic, 'r+b') as f:
        f.seek(512)
        hdr = f.read(92)
        lba, count, size = struct.unpack_from('<QII', hdr, 72)
        f.seek(lba * 512)
        entries = f.read(count * size)
        for i in range(count):
            e = entries[i * size:(i + 1) * size]
            if e[:16] == ptype:
                first, last = struct.unpack_from('<QQ', e, 32)
                break
        else:
            bb.fatal("%s has no data partition" % wic)
        if os.path.getsize(old) > (last - first + 1) * 512:
            bb.fatal("%s is larger than the data partition" % old)
        f.seek(first * 512)
        with open(old, 'rb') as src:
            while True:
                buf = src.read(1 << 20)
                if not buf:
                    break
                f.write(buf)
}
do_image_wic[postfuncs] += "${@'vfpk_test_old_data' if d.getVar('PN') == 'flatpak-minimal-image' else ''}"
