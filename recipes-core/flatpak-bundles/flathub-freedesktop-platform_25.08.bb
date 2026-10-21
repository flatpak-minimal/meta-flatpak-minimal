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
# as Flathub builds it. This build cannot list or check them; the license
# text says where they are recorded. Shipping it means accepting that, so it
# is restricted: set LICENSE_FLAGS_ACCEPTED += "flathub" to build it.
LICENSE = "Freedesktop-SDK-runtime"
NO_GENERIC_LICENSE[Freedesktop-SDK-runtime] = "freedesktop-sdk-runtime.license"
LIC_FILES_CHKSUM = "file://freedesktop-sdk-runtime.license;md5=d92a1cb313768e69c3aa84b8d32beab0"
LICENSE_FLAGS = "flathub"

SRC_URI = "file://freedesktop-sdk-runtime.license"

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
FLATPAK_REMOTE_REFS:x86-64 = " \
    runtime/org.freedesktop.Platform/x86_64/25.08@b7aba340fd291e08bf26442d43a0e4adb6733da5a06d47ff4296a964af40cc8a \
    runtime/org.freedesktop.Platform.GL.default/x86_64/25.08@fe659a591fe882f573584ae62cfb55b92065e4ff7a972833271438bddfa6669e \
"

COMPATIBLE_HOST = "(aarch64|x86_64).*-linux"
