#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Flathub org.freedesktop.Platform 25.08, pinned, for build-time install"
DESCRIPTION = "The freedesktop runtime and its default GL extension, mirrored \
               from Flathub at pinned commits so flatpak-cross-install can \
               install them at build time. Apps from Flathub and bundles \
               built against org.freedesktop.Platform//25.08 need them."
HOMEPAGE = "https://freedesktop-sdk.io"

# An aggregate of hundreds of components under their own licenses, shipped
# as Flathub builds it; this build does not unpack or inspect it.
LICENSE = "CLOSED"

inherit flatpak-bundle

# One copy of the Flathub key in the layer.
FILESEXTRAPATHS:prepend := "${THISDIR}/../flatpak-remotes/files:"

FLATPAK_REMOTE = "flathub"
FLATPAK_REMOTE_URL = "https://dl.flathub.org/repo/"
FLATPAK_REMOTE_GPGKEY = "flathub.gpg"

# Commits from 'flatpak remote-info flathub runtime/<id>/<arch>/25.08'.
# Bump them together; GL.default must match the Platform it extends.
FLATPAK_REMOTE_REFS:aarch64 = " \
    runtime/org.freedesktop.Platform/aarch64/25.08@ef5f18baf428baaf76078a8487da92edf6554f461633f60197c8ee655fd09090 \
    runtime/org.freedesktop.Platform.GL.default/aarch64/25.08@64b5be165afe267110ac521610325c32e9e9c44d2ea9d0ebd2bb199c675dafb5 \
"

# Only aarch64 is pinned so far.
COMPATIBLE_HOST = "aarch64.*-linux"
