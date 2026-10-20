#!/bin/sh
# SPDX-FileCopyrightText: Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vfpk-init.sh: PID 1 of the vfpk guest, installed as /sbin/vfpk-init.
#
# Runs one command handed over by vfpk-runner.sh, then writes the results
# back and powers the guest off. All exchange is through virtio disks found
# by serial number (see vfpk-runner.sh for the list).
#
# Modeled on meta-virtualization's vcontainer-init-common.sh and
# vpdmn-init.sh (commit 7b0154418de3350fd23a0bd868742f2b570b24d3).

PATH=/usr/sbin:/usr/bin:/sbin:/bin
HOME=/root
export PATH HOME

RESULT_DIR=/run/vfpk-result
CONTROL_DIR=/run/vfpk
FLATPAK_DIR=/var/lib/flatpak
INPUT_DIR=/mnt/input

mountpoint -q /proc || mount -t proc proc /proc
mountpoint -q /sys || mount -t sysfs sysfs /sys
mountpoint -q /dev || mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm
mount -t devpts devpts /dev/pts
mount -t tmpfs -o mode=1777 tmpfs /dev/shm
mount -t tmpfs -o mode=0755 tmpfs /run
mount -t tmpfs -o mode=1777 tmpfs /tmp
# /var/tmp and /var/log point into /var/volatile on a Yocto rootfs. flatpak
# stages bundles in /var/tmp.
mkdir -p /var/volatile
mount -t tmpfs -o mode=0755 tmpfs /var/volatile
mkdir -p /var/volatile/tmp /var/volatile/log
chmod 1777 /var/volatile/tmp
ip link set lo up 2>/dev/null

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

power_off() {
    sync
    umount "$FLATPAK_DIR" 2>/dev/null
    umount "$INPUT_DIR" 2>/dev/null
    sync
    # QEMU runs with -no-reboot, so a reboot ends the VM.
    reboot -f
}

RESULT_DEV=""

# Write the result tar. Without it the runner reports a failed run, so the
# command's own exit status must not be the only thing that survives.
write_result() {
    mkdir -p "$RESULT_DIR"
    echo "$1" > "$RESULT_DIR/exit-code"
    # The result disk is 16 MB; keep the tail of a long output rather than
    # lose the exit code with it.
    if [ -f "$RESULT_DIR/output.txt" ] && [ "$(stat -c %s "$RESULT_DIR/output.txt")" -gt 8388608 ]; then
        tail -c 8388608 "$RESULT_DIR/output.txt" > /tmp/output.tail
        mv /tmp/output.tail "$RESULT_DIR/output.txt"
    fi
    if [ -n "$RESULT_DEV" ]; then
        tar -cf "$RESULT_DEV" -C "$RESULT_DIR" . || echo "===VFPK_ERROR=== cannot write the result disk"
    fi
    sync
    echo "===VFPK_DONE=== exit code $1"
}

fail() {
    echo "===VFPK_ERROR=== $*"
    mkdir -p "$RESULT_DIR"
    echo "vfpk-init: $*" >> "$RESULT_DIR/output.txt"
    write_result 125
    power_off
}

RESULT_DEV=$(find_disk vfpk-result) || fail "no disk with serial vfpk-result"

CONTROL_DEV=$(find_disk vfpk-control) || fail "no disk with serial vfpk-control"
mkdir -p "$CONTROL_DIR"
tar -xf "$CONTROL_DEV" -C "$CONTROL_DIR" || fail "cannot read the control disk"
[ -f "$CONTROL_DIR/cmd" ] || fail "the control disk has no command"

option() {
    sed -n "s/^$1=//p" "$CONTROL_DIR/options" 2>/dev/null
}

[ "$(option verbose)" = "1" ] && set -x

mkdir -p "$INPUT_DIR"
if INPUT_DEV=$(find_disk vfpk-input); then
    # noload: never replay a journal on a disk mounted read-only.
    mount -t ext4 -o ro,noload "$INPUT_DEV" "$INPUT_DIR" || fail "cannot mount the input disk"
fi

WORK_DEV=$(find_disk vfpk-work) || fail "no disk with serial vfpk-work"
mkdir -p "$FLATPAK_DIR"
mount -t ext4 "$WORK_DEV" "$FLATPAK_DIR" || fail "cannot mount the work disk"

if [ "$(option network)" = "1" ]; then
    # QEMU user-mode networking: fixed addresses, no DHCP client needed.
    ip link set eth0 up || fail "no network interface"
    ip addr add 10.0.2.15/24 dev eth0
    ip route add default via 10.0.2.2
    rm -f /etc/resolv.conf
    echo "nameserver 10.0.2.3" > /etc/resolv.conf
fi

export VFPK_INPUT="$INPUT_DIR"
mkdir -p "$RESULT_DIR"
cd / || fail "cannot change to /"
sh "$CONTROL_DIR/cmd" > "$RESULT_DIR/output.txt" 2>&1 < /dev/null
rc=$?
sync

if [ "$(option output)" = "1" ]; then
    STORAGE_DEV=$(find_disk vfpk-storage) || fail "no disk with serial vfpk-storage"
    # Numeric owners: the tar is unpacked on the build host, whose user
    # database has nothing to do with the guest's. GNU tar reports the
    # archive size, which the runner needs to cut the tar out of the disk.
    if tar --numeric-owner --totals -cf "$STORAGE_DEV" -C "$FLATPAK_DIR" \
            --exclude=./lost+found --exclude=./repo/tmp/cache . 2> /tmp/storage.err; then
        sed -n 's/^Total bytes written: \([0-9]*\).*/\1/p' /tmp/storage.err > "$RESULT_DIR/storage-bytes"
    else
        cp /tmp/storage.err "$RESULT_DIR/storage-error"
    fi
fi

write_result "$rc"
power_off
