#!/bin/sh
# SPDX-FileCopyrightText: Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# vfpk-growpart LABEL: extend the partition holding the filesystem labeled
# LABEL to the end of its disk. The image ships the flatpak data partition
# no larger than its content; this gives it the rest of the device.
#
# It only grows a partition that is the last one on its disk, and does nothing
# once that partition reaches the end, so it is safe to run on every boot.
# The filesystem is grown afterwards by systemd-growfs (x-systemd.growfs).

set -eu

LABEL=${1:?usage: vfpk-growpart LABEL}

log() { echo "vfpk-growpart: $*"; }

dev=$(readlink -f "/dev/disk/by-label/$LABEL" 2>/dev/null) || dev=
if [ -z "$dev" ] || [ ! -b "$dev" ]; then
    log "no filesystem labeled $LABEL; nothing to grow"
    exit 0
fi

part=${dev##*/}
sys=/sys/class/block/$part
if [ ! -f "$sys/partition" ]; then
    log "$dev is not a partition; nothing to grow"
    exit 0
fi
num=$(cat "$sys/partition")
diskname=$(basename "$(readlink -f "$sys/..")")
disk=/dev/$diskname

# sysfs counts in 512-byte sectors whatever the logical block size.
start=$(cat "$sys/start")
size=$(cat "$sys/size")
total=$(cat "/sys/class/block/$diskname/size")

for other in /sys/class/block/"$diskname"/*/partition; do
    [ -f "$other" ] || continue
    if [ "$(cat "${other%/partition}/start")" -gt "$start" ]; then
        log "$dev is not the last partition on $disk; leaving it as it is"
        exit 0
    fi
done

label=$(sfdisk --dump "$disk" 2>/dev/null | sed -n 's/^label: *//p')
# sfdisk counts in logical sectors, sysfs and resizepart in 512-byte ones.
factor=$(($(cat "/sys/class/block/$diskname/queue/logical_block_size") / 512))
end=$total
case "$label" in
    dos)
        # A logical partition sits inside the extended one, which would have
        # to grow first.
        if [ "$num" -gt 4 ]; then
            log "$dev is a logical partition; leaving it as it is"
            exit 0
        fi
        # An MBR entry ends within 2^32 sectors; the rest of a larger disk
        # is out of its reach.
        max=$((4294967296 * factor))
        [ "$end" -le "$max" ] || end=$max
        ;;
    gpt) ;;
    *)
        log "$disk has no dos or gpt partition table; nothing to grow"
        exit 0
        ;;
esac

# Past a grown partition only the backup GPT (33 sectors) and the alignment
# of its end to 1 MiB remain; under 2 MiB is full. Checked before anything is
# written, so later boots write nothing.
if [ $((end - start - size)) -lt 4096 ]; then
    log "$dev already fills $disk"
    exit 0
fi

if [ "$label" = gpt ]; then
    # A raw image written to a larger disk keeps its backup GPT where the
    # image ended; move it to the end of the disk first.
    sfdisk --no-reread --no-tell-kernel --relocate gpt-bak-std "$disk"
fi

# ", +" keeps the start and takes all the free space after it. resizepart
# tells the kernel the new size in place: partx --update would delete and
# re-add the unmounted partition, and systemd would drop the mounts waiting
# on its device.
echo ', +' | sfdisk --no-reread --no-tell-kernel --quiet -N "$num" "$disk"
grown=$(sfdisk --dump "$disk" | sed -n "s|^$dev : .*size= *\([0-9]*\).*|\1|p")
case "$grown" in
    ''|*[!0-9]*|0)
        log "cannot read the new size of $dev from $disk"
        exit 1
        ;;
esac
resizepart "$disk" "$num" $((grown * factor))

new=$(cat "$sys/size")
log "grew $dev from $((size / 2048)) MiB to $((new / 2048)) MiB"
