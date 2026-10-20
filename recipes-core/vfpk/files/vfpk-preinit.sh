#!/bin/sh
# SPDX-FileCopyrightText: Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vfpk-preinit.sh: /init of the vfpk tiny initramfs.
#
# Mounts the squashfs root filesystem (the virtio disk with serial
# vfpk-rootfs) under a tmpfs overlay and switches to it, running the init
# named by vfpk.init= on the kernel command line.
#
# Modeled on meta-virtualization's vcontainer-preinit.sh (commit
# 7b0154418de3350fd23a0bd868742f2b570b24d3).

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

fail() {
    echo "===VFPK_ERROR=== preinit: $*"
    sleep 1
    reboot -f
}

INIT=/sbin/vfpk-init
read -r CMDLINE < /proc/cmdline
# shellcheck disable=SC2086 # split the command line into words
for param in $CMDLINE; do
    case "$param" in
        vfpk.init=*) INIT=${param#vfpk.init=} ;;
    esac
done

find_disk() {
    for blk in /sys/block/vd*; do
        [ -e "$blk/serial" ] || continue
        if [ "$(cat "$blk/serial")" = "$1" ]; then
            echo "/dev/${blk##*/}"
            return 0
        fi
    done
    return 1
}

# virtio-blk probes asynchronously; poll for up to ten seconds.
i=0
while ! ROOTFS_DEV=$(find_disk vfpk-rootfs) || [ ! -b "$ROOTFS_DEV" ]; do
    i=$((i + 1))
    [ "$i" -le 1000 ] || fail "no disk with serial vfpk-rootfs"
    sleep 0.01
done

mkdir -p /mnt/lower /mnt/rw /mnt/root
mount -t squashfs -o ro "$ROOTFS_DEV" /mnt/lower || fail "cannot mount $ROOTFS_DEV"

# Writes to the root filesystem stay in memory; the flatpak installation
# itself lives on its own disk, so this only holds logs and scratch files.
mount -t tmpfs -o mode=0755 tmpfs /mnt/rw || fail "cannot mount the overlay tmpfs"
mkdir -p /mnt/rw/upper /mnt/rw/work
mount -t overlay overlay \
    -o lowerdir=/mnt/lower,upperdir=/mnt/rw/upper,workdir=/mnt/rw/work /mnt/root \
    || fail "cannot mount the overlay root"

[ -x "/mnt/root$INIT" ] || fail "$INIT not found in the root filesystem"

mount --move /proc /mnt/root/proc
mount --move /sys /mnt/root/sys
mount --move /dev /mnt/root/dev

exec switch_root /mnt/root "$INIT"
