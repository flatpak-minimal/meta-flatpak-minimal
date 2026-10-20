#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vfpk-runner.sh: run one command in a vfpk QEMU guest and collect the flatpak
# system installation (/var/lib/flatpak) it leaves behind.
#
# Modeled on meta-virtualization's vrunner.sh and vrunner-backend-qemu.sh
# (commit 7b0154418de3350fd23a0bd868742f2b570b24d3), reduced to a single
# batch job: no daemon mode, no Xen, no interactive mode, no registry auth.
#
# Unlike vrunner, nothing travels over the kernel command line or a 9p share.
# Every exchange with the guest is a virtio-blk disk, identified by its serial
# number rather than by probe order:
#
#   vfpk-rootfs   squashfs guest root filesystem (read-only)
#   vfpk-control  tar with the command and options (read-only)
#   vfpk-input    ext4 built from --input, mounted at /mnt/input (read-only)
#   vfpk-work     ext4 mounted at /var/lib/flatpak, seeded from --input-storage
#   vfpk-result   raw tar the guest writes: exit code and command output
#   vfpk-storage  raw tar the guest writes: the whole /var/lib/flatpak
#
# A tar written to a raw disk keeps ownership, modes and hardlinks, which a 9p
# share with security_model=none does not, and needs no virtfs support in QEMU.

set -euo pipefail

PROG=${0##*/}

ARCH=""
BLOB_DIR=""
INPUT=""
INPUT_STORAGE=""
OUTPUT=""
WORK_MB=""
TIMEOUT=1800
MEMORY=2048
SMP=""
NETWORK=0
KEEP_TEMP=0
VERBOSE=0
COMMAND=""

usage() {
    cat <<EOF
Usage: $PROG --arch ARCH --blob-dir DIR [options] -- COMMAND

Boot the vfpk guest for ARCH and run COMMAND with /bin/sh as root. The
command sees the input directory at \$VFPK_INPUT (/mnt/input) and the flatpak
system installation at /var/lib/flatpak. Its output is printed on stdout and
its exit status becomes the exit status of $PROG.

Options:
  --arch ARCH            aarch64, x86_64, riscv64 or arm
  --blob-dir DIR         directory with the kernel, initramfs.cpio.gz and
                         rootfs.img built by vfpk-initramfs-create
  --input DIR            directory to expose read-only at /mnt/input
  --input-storage TAR    tar of an existing /var/lib/flatpak to start from
  --output TAR           write /var/lib/flatpak as a tar to TAR afterwards
  --work-size MB         size of the /var/lib/flatpak disk (sparse; default
                         derived from the inputs, at least 8192)
  --timeout SECONDS      kill the guest after this long (default $TIMEOUT)
  --memory MB            guest memory (default $MEMORY)
  --smp N                guest CPUs (default: up to 4)
  --network              give the guest user-mode networking
  --keep-temp            keep the working directory for debugging
  --verbose              print the guest console when the run fails or succeeds
  -h, --help             show this help
EOF
}

log() {
    echo "$PROG: $*" >&2
}

die() {
    log "error: $*"
    exit 125
}

is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --arch) ARCH=${2:-}; shift 2 ;;
        --blob-dir) BLOB_DIR=${2:-}; shift 2 ;;
        --input) INPUT=${2:-}; shift 2 ;;
        --input-storage) INPUT_STORAGE=${2:-}; shift 2 ;;
        --output) OUTPUT=${2:-}; shift 2 ;;
        --work-size) WORK_MB=${2:-}; shift 2 ;;
        --timeout) TIMEOUT=${2:-}; shift 2 ;;
        --memory) MEMORY=${2:-}; shift 2 ;;
        --smp) SMP=${2:-}; shift 2 ;;
        --network) NETWORK=1; shift ;;
        --keep-temp) KEEP_TEMP=1; shift ;;
        --verbose) VERBOSE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; COMMAND="$*"; break ;;
        *) usage >&2; die "unknown argument: $1" ;;
    esac
done

[ -n "$ARCH" ] || die "--arch is required"
[ -n "$BLOB_DIR" ] || die "--blob-dir is required"
[ -n "$COMMAND" ] || die "no command given after --"
[ -d "$BLOB_DIR" ] || die "blob directory not found: $BLOB_DIR"
[ -z "$INPUT" ] || [ -d "$INPUT" ] || die "input directory not found: $INPUT"
[ -z "$INPUT_STORAGE" ] || [ -f "$INPUT_STORAGE" ] || die "input storage not found: $INPUT_STORAGE"
is_uint "$TIMEOUT" && [ "$TIMEOUT" -gt 0 ] || die "--timeout must be a positive integer"
is_uint "$MEMORY" && [ "$MEMORY" -ge 512 ] || die "--memory must be at least 512"
[ -z "$WORK_MB" ] || is_uint "$WORK_MB" || die "--work-size must be an integer"
[ -z "$SMP" ] || { is_uint "$SMP" && [ "$SMP" -gt 0 ]; } || die "--smp must be a positive integer"

# Architecture table. Machine and CPU follow oe-core's qemu machine configs
# (QB_MACHINE/QB_CPU), so the guest userspace tune is supported.
case "$ARCH" in
    aarch64)
        QEMU=qemu-system-aarch64
        KERNEL_NAME=Image
        CONSOLE=ttyAMA0
        MACHINE_TCG="virt"
        CPU_TCG="cortex-a57"
        MACHINE_KVM="virt,gic-version=max"
        ;;
    x86_64)
        QEMU=qemu-system-x86_64
        KERNEL_NAME=bzImage
        CONSOLE=ttyS0
        MACHINE_TCG="q35"
        CPU_TCG="Skylake-Client"
        MACHINE_KVM="q35"
        ;;
    riscv64)
        QEMU=qemu-system-riscv64
        KERNEL_NAME=Image
        CONSOLE=ttyS0
        MACHINE_TCG="virt"
        CPU_TCG="rva23s64,pmp=true"
        MACHINE_KVM=""
        ;;
    arm)
        QEMU=qemu-system-arm
        KERNEL_NAME=zImage
        CONSOLE=ttyAMA0
        MACHINE_TCG="virt,highmem=off"
        CPU_TCG="cortex-a15"
        MACHINE_KVM=""
        ;;
    *)
        die "unsupported architecture: $ARCH"
        ;;
esac

KERNEL="$BLOB_DIR/$KERNEL_NAME"
INITRAMFS="$BLOB_DIR/initramfs.cpio.gz"
ROOTFS="$BLOB_DIR/rootfs.img"
for f in "$KERNEL" "$INITRAMFS" "$ROOTFS"; do
    [ -f "$f" ] || die "missing guest blob: $f"
done

command -v "$QEMU" >/dev/null 2>&1 || die "$QEMU not found on PATH"
command -v mke2fs >/dev/null 2>&1 || die "mke2fs not found on PATH"

# KVM only when the guest is the host's own architecture and /dev/kvm is
# usable; TCG otherwise.
ACCEL="tcg"
QEMU_MACHINE="$MACHINE_TCG"
QEMU_CPU="$CPU_TCG"
if [ -n "$MACHINE_KVM" ] && [ "$(uname -m)" = "$ARCH" ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL="kvm"
    QEMU_MACHINE="$MACHINE_KVM"
    QEMU_CPU="host"
fi

if [ -z "$SMP" ]; then
    SMP=$(nproc 2>/dev/null || echo 1)
    [ "$SMP" -le 4 ] || SMP=4
fi

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/vfpk-runner.XXXXXXXX")
QEMU_PID=""

# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() {
    if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill -9 "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
    fi
    if [ "$KEEP_TEMP" = "1" ]; then
        log "working directory kept: $WORKDIR"
    else
        rm -rf "$WORKDIR"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

du_mb() {
    # Apparent size is what mke2fs -d has to store. No -L: absolute symlinks
    # must not be followed into the host.
    local kb
    kb=$(du -sk "$1" | cut -f1)
    echo $(( (kb + 1023) / 1024 ))
}

# Control disk: the command and the options, as a plain tar.
mkdir -p "$WORKDIR/control"
printf '%s\n' "$COMMAND" > "$WORKDIR/control/cmd"
{
    echo "output=$([ -n "$OUTPUT" ] && echo 1 || echo 0)"
    echo "network=$NETWORK"
    echo "verbose=$VERBOSE"
} > "$WORKDIR/control/options"
tar -cf "$WORKDIR/control.img" -C "$WORKDIR/control" --owner=0 --group=0 --numeric-owner .
truncate -s 1M "$WORKDIR/control.img"

# Input disk. ext4 overhead grows with the content, so give content + 30% +
# 64 MB and drop the reserved blocks (vrunner.sh learned this the hard way).
# Do not silence mke2fs: a short -d copy must fail here, not in the guest.
INPUT_MB=0
if [ -n "$INPUT" ]; then
    INPUT_MB=$(du_mb "$INPUT")
    size=$(( INPUT_MB * 130 / 100 + 64 ))
    truncate -s "${size}M" "$WORKDIR/input.img"
    if ! mke2fs -q -t ext4 -m 0 -F -E lazy_itable_init=1,lazy_journal_init=1 \
            -d "$INPUT" "$WORKDIR/input.img" > "$WORKDIR/mke2fs-input.log" 2>&1; then
        cat "$WORKDIR/mke2fs-input.log" >&2
        die "mke2fs failed for the input disk (${size} MB)"
    fi
fi

# Work disk, mounted at /var/lib/flatpak in the guest. It is sparse, so a
# generous size costs nothing until the guest writes to it.
STORAGE_MB=0
if [ -n "$INPUT_STORAGE" ]; then
    STORAGE_MB=$(( ($(stat -c %s "$INPUT_STORAGE") + 1048575) / 1048576 ))
fi
if [ -z "$WORK_MB" ]; then
    WORK_MB=$(( INPUT_MB * 3 + STORAGE_MB * 2 + 4096 ))
    [ "$WORK_MB" -ge 8192 ] || WORK_MB=8192
fi
truncate -s "${WORK_MB}M" "$WORKDIR/work.img"
work_src=()
if [ -n "$INPUT_STORAGE" ]; then
    mkdir -p "$WORKDIR/storage-in"
    tar -xf "$INPUT_STORAGE" -C "$WORKDIR/storage-in"
    work_src=(-d "$WORKDIR/storage-in")
fi
if ! mke2fs -q -t ext4 -m 0 -F -E lazy_itable_init=1,lazy_journal_init=1 \
        "${work_src[@]}" "$WORKDIR/work.img" > "$WORKDIR/mke2fs-work.log" 2>&1; then
    cat "$WORKDIR/mke2fs-work.log" >&2
    die "mke2fs failed for the work disk (${WORK_MB} MB)"
fi
rm -rf "$WORKDIR/storage-in"

# Result disks. The storage tar cannot be larger than the work filesystem
# plus tar headers, so size it from the work disk.
truncate -s 16M "$WORKDIR/result.img"
if [ -n "$OUTPUT" ]; then
    truncate -s "$(( WORK_MB + WORK_MB / 8 + 64 ))M" "$WORKDIR/storage.img"
fi

# QEMU splits option strings on commas; a literal comma is written twice.
qemu_escape() {
    printf '%s' "${1//,/,,}"
}

disk() {
    # disk SERIAL FILE [readonly]
    local ro=""
    [ "${3:-}" = "readonly" ] && ro=",readonly=on"
    QEMU_ARGS+=(-drive "if=none,id=$1,file=$(qemu_escape "$2"),format=raw,cache=writeback$ro"
                -device "virtio-blk-pci,drive=$1,serial=$1")
}

QEMU_ARGS=(
    -nodefaults -no-user-config
    -machine "$QEMU_MACHINE" -accel "$ACCEL" -cpu "$QEMU_CPU"
    -m "$MEMORY" -smp "$SMP"
    -display none -monitor none -serial "file:$(qemu_escape "$WORKDIR/console.log")"
    -no-reboot
    -kernel "$KERNEL" -initrd "$INITRAMFS"
    -append "console=$CONSOLE panic=-1 vfpk.init=/sbin/vfpk-init"
)
disk vfpk-rootfs "$ROOTFS" readonly
disk vfpk-control "$WORKDIR/control.img" readonly
[ -z "$INPUT" ] || disk vfpk-input "$WORKDIR/input.img" readonly
disk vfpk-work "$WORKDIR/work.img"
disk vfpk-result "$WORKDIR/result.img"
[ -z "$OUTPUT" ] || disk vfpk-storage "$WORKDIR/storage.img"
if [ "$NETWORK" = "1" ]; then
    QEMU_ARGS+=(-netdev "user,id=net0" -device "virtio-net-pci,netdev=net0")
else
    QEMU_ARGS+=(-nic none)
fi

log "booting $ARCH guest ($ACCEL, ${SMP} CPUs, ${MEMORY} MB, timeout ${TIMEOUT}s)"
start=$(date +%s)
"$QEMU" "${QEMU_ARGS[@]}" </dev/null >"$WORKDIR/qemu.log" 2>&1 &
QEMU_PID=$!

qemu_rc=0
timed_out=0
while kill -0 "$QEMU_PID" 2>/dev/null; do
    if [ $(( $(date +%s) - start )) -ge "$TIMEOUT" ]; then
        timed_out=1
        kill -9 "$QEMU_PID" 2>/dev/null || true
        break
    fi
    sleep 1
done
wait "$QEMU_PID" || qemu_rc=$?
QEMU_PID=""
log "guest finished after $(( $(date +%s) - start ))s"

show_console() {
    log "QEMU output:"
    sed 's/^/  /' "$WORKDIR/qemu.log" >&2 || true
    log "guest console:"
    sed 's/^/  /' "$WORKDIR/console.log" >&2 || true
}

[ "$timed_out" = "0" ] || { show_console; die "guest timed out after ${TIMEOUT}s"; }

mkdir -p "$WORKDIR/result"
if ! tar -xf "$WORKDIR/result.img" -C "$WORKDIR/result" 2>/dev/null \
        || [ ! -f "$WORKDIR/result/exit-code" ]; then
    show_console
    die "guest wrote no result (QEMU exit status $qemu_rc)"
fi

[ "$VERBOSE" = "0" ] || show_console
cat "$WORKDIR/result/output.txt" 2>/dev/null || true

exit_code=$(cat "$WORKDIR/result/exit-code")
is_uint "$exit_code" || die "guest reported a malformed exit code: $exit_code"

if [ -n "$OUTPUT" ]; then
    [ ! -f "$WORKDIR/result/storage-error" ] || {
        sed 's/^/  /' "$WORKDIR/result/storage-error" >&2
        die "guest failed to write the storage tar"
    }
    bytes=$(cat "$WORKDIR/result/storage-bytes" 2>/dev/null || true)
    is_uint "$bytes" && [ "$bytes" -gt 0 ] || die "guest reported no storage size"
    [ "$bytes" -le "$(stat -c %s "$WORKDIR/storage.img")" ] || die "storage size $bytes exceeds the disk"
    head -c "$bytes" "$WORKDIR/storage.img" > "$OUTPUT.tmp"
    tar -tf "$OUTPUT.tmp" > /dev/null || { rm -f "$OUTPUT.tmp"; die "storage tar is corrupt"; }
    mv "$OUTPUT.tmp" "$OUTPUT"
    log "wrote $OUTPUT ($(( bytes / 1048576 )) MB)"
fi

if [ "$exit_code" != "0" ]; then
    log "guest command failed with exit status $exit_code"
    [ "$VERBOSE" = "1" ] || show_console
fi
exit "$exit_code"
