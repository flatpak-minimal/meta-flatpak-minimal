#!/bin/sh
set -e

ROOT_DEV=$(findmnt -no SOURCE --target /)
ROOT_DEV=$(readlink -f "$ROOT_DEV")
DISK_NAME=$(lsblk -no PKNAME "$ROOT_DEV")
PART_NUM=$(lsblk -no PARTN "$ROOT_DEV")

if [ -z "$DISK_NAME" ] || [ -z "$PART_NUM" ]; then
    echo "expand-rootfs: could not resolve $ROOT_DEV to a disk and partition number, skipping" >&2
    exit 0
fi

DISK="/dev/$DISK_NAME"

parted -s -f "$DISK" resizepart "$PART_NUM" 100%
udevadm settle

FSTYPE=$(findmnt -no FSTYPE --target /)
case "$FSTYPE" in
    ext2|ext3|ext4)
        resize2fs "$ROOT_DEV"
        ;;
    xfs)
        xfs_growfs /
        ;;
    btrfs)
        btrfs filesystem resize max /
        ;;
    *)
        echo "expand-rootfs: partition grown but filesystem '$FSTYPE' is not one this script knows how to resize" >&2
        ;;
esac
