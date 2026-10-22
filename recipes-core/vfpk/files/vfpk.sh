#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vfpk: keep a flatpak system installation for a target architecture on a
# development host, and install into it or run from it in the vfpk guest.
#
# The installation lives in a tar of /var/lib/flatpak (--state). Each command
# boots the guest with it, runs flatpak there and saves the result back, so
# the tar is what a device would have after the same commands.

set -euo pipefail

PROG=${0##*/}
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

ARCH=${VFPK_ARCH:-}
BLOB_DIR=${VFPK_BLOB_DIR:-}
STATE=${VFPK_STATE:-}
INPUT=""
RUNNER_ARGS=()

usage() {
    cat <<EOF
Usage: $PROG [options] COMMAND [ARGS...]

Commands:
  install BUNDLE...         install .flatpak bundles from the host
  install REPO REF...       install REFs from a local ostree repository, such
                            as deploy/flatpak/repo-dev, added as remote
                            vfpk-local
  flatpak ARGS...           run flatpak in the guest ('flatpak list',
                            'flatpak remote-add ...', 'flatpak update -y')
  run APP [ARGS...]         run APP in the guest; nothing is saved
  sh COMMAND                run COMMAND with /bin/sh in the guest
  reset                     delete the installation

Options:
  --arch ARCH               aarch64, x86_64, riscv64 or arm (\$VFPK_ARCH;
                            default: the only arch the blob directory has)
  --blob-dir DIR            guest kernel, initramfs and rootfs (\$VFPK_BLOB_DIR;
                            default: the blobs shipped next to $PROG)
  --state FILE              tar of the installation (\$VFPK_STATE; default
                            \${XDG_DATA_HOME:-~/.local/share}/vfpk/ARCH/flatpak.tar)
  --input DIR               expose DIR in the guest at \$VFPK_INPUT
  --network                 give the guest network access, for remotes
  --memory MB, --smp N, --timeout SECONDS, --verbose
                            passed to vfpk-runner.sh

The state tar has numeric owners. Unpacked as root into /var/lib/flatpak on a
device of the same architecture, it is the installation built here.
EOF
}

log() {
    echo "$PROG: $*" >&2
}

die() {
    log "error: $*"
    exit 125
}

# Quote for /bin/sh in the guest.
shq() {
    printf "'%s'" "${1//\'/\'\\\'\'}"
}

shq_all() {
    local arg out=""
    for arg in "$@"; do
        out+=" $(shq "$arg")"
    done
    printf '%s' "${out# }"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --arch) ARCH=${2:-}; shift 2 ;;
        --blob-dir) BLOB_DIR=${2:-}; shift 2 ;;
        --state) STATE=${2:-}; shift 2 ;;
        --input) INPUT=${2:-}; shift 2 ;;
        --network|--verbose) RUNNER_ARGS+=("$1"); shift ;;
        --memory|--smp|--timeout) RUNNER_ARGS+=("$1" "${2:-}"); shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*) usage >&2; die "unknown option: $1" ;;
        *) break ;;
    esac
done

[ $# -gt 0 ] || { usage >&2; die "no command given"; }
CMD=$1
shift

# The standalone tarball ships its QEMU and mke2fs in an SDK sysroot next to
# this script; prefer them over the host's.
for dir in "$HERE"/sysroots/*/usr/bin "$HERE"/sysroots/*/usr/sbin; do
    [ -d "$dir" ] && PATH="$dir:$PATH"
done
export PATH

RUNNER="$HERE/vfpk-runner.sh"
[ -x "$RUNNER" ] || RUNNER=$(command -v vfpk-runner.sh) || die "vfpk-runner.sh not found"

if [ -z "$BLOB_DIR" ]; then
    if [ -z "$ARCH" ]; then
        shopt -s nullglob
        dirs=("$HERE"/blobs/*/)
        shopt -u nullglob
        [ "${#dirs[@]}" -eq 1 ] || die "--arch is required (blobs: ${#dirs[@]})"
        ARCH=$(basename "${dirs[0]}")
    fi
    BLOB_DIR="$HERE/blobs/$ARCH"
fi
[ -d "$BLOB_DIR" ] || die "blob directory not found: $BLOB_DIR"
# A build tree's blob directory is .../vfpk/ARCH.
[ -n "$ARCH" ] || ARCH=$(basename "$(cd "$BLOB_DIR" && pwd)")
case "$ARCH" in
    aarch64|x86_64|riscv64|arm) ;;
    *) die "unsupported architecture: $ARCH" ;;
esac

[ -n "$STATE" ] || STATE="${XDG_DATA_HOME:-$HOME/.local/share}/vfpk/$ARCH/flatpak.tar"
mkdir -p "$(dirname "$STATE")"
STATE=$(cd "$(dirname "$STATE")" && pwd)/$(basename "$STATE")

# The runner's sparse disks hold a copy of the installation; keep them off a
# tmpfs /tmp unless TMPDIR says otherwise.
export TMPDIR=${TMPDIR:-$(dirname "$STATE")}

if command -v flock >/dev/null 2>&1; then
    exec 9>"$STATE.lock"
    flock -n 9 || die "another $PROG command is using $STATE"
fi

STAGE=""
# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() {
    [ -z "$STAGE" ] || rm -rf "$STAGE"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# stage SRC...: hard-link or copy SRC into a fresh input directory.
stage() {
    local src
    [ -z "$INPUT" ] || die "--input cannot be combined with install"
    STAGE=$(mktemp -d "$TMPDIR/vfpk-input.XXXXXXXX")
    for src in "$@"; do
        [ ! -e "$STAGE/$(basename "$src")" ] || die "two inputs named $(basename "$src")"
        cp -al "$src" "$STAGE/" 2>/dev/null || cp -a "$src" "$STAGE/" \
            || die "cannot stage $src"
    done
    INPUT=$STAGE
}

# guest SAVE SCRIPT: run SCRIPT in the guest. With SAVE, the installation is
# saved back when SCRIPT succeeds.
guest() {
    local rc=0
    local args=(--arch "$ARCH" --blob-dir "$BLOB_DIR" "${RUNNER_ARGS[@]}")
    [ -z "$INPUT" ] || args+=(--input "$INPUT")
    [ ! -f "$STATE" ] || args+=(--input-storage "$STATE")
    [ "$1" = "0" ] || args+=(--output "$STATE.new")
    "$RUNNER" "${args[@]}" -- "$2" || rc=$?
    if [ "$1" != "0" ]; then
        if [ "$rc" = "0" ]; then
            mv "$STATE.new" "$STATE"
        else
            rm -f "$STATE.new"
            log "$STATE left unchanged"
        fi
    fi
    return "$rc"
}

case "$CMD" in
    install)
        [ $# -gt 0 ] || die "install needs a bundle or a repository"
        if [ -d "$1" ]; then
            [ -f "$1/config" ] && [ -d "$1/objects" ] || die "not an ostree repository: $1"
            [ $# -gt 1 ] || die "install from a repository needs at least one ref"
            repo=$1
            shift
            stage "$repo"
            url="file:///mnt/input/$(basename "$repo")"
            guest 1 "set -e
flatpak remote-add --system --if-not-exists --no-gpg-verify vfpk-local $(shq "$url")
flatpak remote-modify --system --url=$(shq "$url") vfpk-local
flatpak install --system --noninteractive --or-update vfpk-local $(shq_all "$@")"
        else
            script="set -e"
            for f in "$@"; do
                [ -f "$f" ] || die "bundle not found: $f"
            done
            stage "$@"
            for f in "$@"; do
                script+="
flatpak install --system --noninteractive --or-update --bundle \"\$VFPK_INPUT\"/$(shq "$(basename "$f")")"
            done
            guest 1 "$script"
        fi
        ;;
    flatpak)
        [ $# -gt 0 ] || die "flatpak needs arguments"
        guest 1 "flatpak $(shq_all "$@")"
        ;;
    run)
        [ $# -gt 0 ] || die "run needs an app"
        [ -f "$STATE" ] || die "no installation at $STATE"
        guest 0 "mkdir -p -m 0700 /run/user/0
export XDG_RUNTIME_DIR=/run/user/0
flatpak run $(shq_all "$@")"
        ;;
    sh)
        [ $# -eq 1 ] || die "sh takes one command string"
        guest 1 "$1"
        ;;
    reset)
        rm -f "$STATE"
        log "removed $STATE"
        ;;
    *)
        usage >&2
        die "unknown command: $CMD"
        ;;
esac
