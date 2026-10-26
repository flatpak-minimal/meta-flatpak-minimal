#!/bin/sh
# SPDX-FileCopyrightText: Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# vfpk-seed: unpack the flatpak installation seeded at build time into the
# writable /var/lib/flatpak, once. A per-user seed unit sets VFPK_SEED_DIR
# to the user's installation and runs this script as that user.
#
# The marker makes it run once per installation, and an existing
# installation is never touched: apps the user installed or updated in the
# field survive an OS update that brings a newer seed. An interrupted run
# leaves no marker and starts over on the next boot.

set -eu

SEED=@SEED@
DIR=${VFPK_SEED_DIR:-@DIR@}
MARKER=$DIR/.vfpk-seeded
TMP=$DIR/.vfpk-seed.tmp

[ -f "$SEED" ] || exit 0
[ ! -e "$MARKER" ] || exit 0
mkdir -p "$DIR"

if [ -e "$DIR/repo" ]; then
    echo "vfpk-seed: $DIR already holds an installation; leaving it as it is"
    touch "$MARKER"
    exit 0
fi

# Unpack beside the installation, on the same filesystem, then move each
# top-level entry into place with a rename. repo goes last, so its presence
# means everything else is in place.
rm -rf "$TMP"
mkdir "$TMP"
tar -xf "$SEED" -C "$TMP"
for entry in "$TMP"/* "$TMP"/.[!.]*; do
    [ -e "$entry" ] || continue
    [ "${entry##*/}" = repo ] && continue
    rm -rf "${DIR:?}/${entry##*/}"
    mv "$entry" "$DIR/"
done
if [ -d "$TMP/repo" ]; then
    mv "$TMP/repo" "$DIR/repo"
fi
rmdir "$TMP"
sync
touch "$MARKER"
sync
echo "vfpk-seed: unpacked $SEED into $DIR"
