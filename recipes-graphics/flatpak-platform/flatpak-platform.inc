#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# org.flatpak_minimal.Platform and org.flatpak_minimal.Sdk: the layer's base
# runtime and its SDK. A Wayland and GLES userspace with fonts and
# certificates, and nothing toolkit-specific: toolkits come as extensions
# (org.flatpak_minimal.Flutter.Engine.<mode>) or in the apps. The branch is the
# oe-core release, FLATPAK_PLATFORM_BRANCH.

REQUIRED_DISTRO_FEATURES = "opengl usrmerge wayland"

FLATPAK_RUNTIME_BRANCH = "${FLATPAK_PLATFORM_BRANCH}"

# General-purpose libraries go here rather than into an extension that
# happens to need them first, so every extension and app shares one copy.
FLATPAK_PLATFORM_PACKAGES = "\
    busybox \
    ca-certificates \
    fontconfig \
    glib-2.0 \
    gstreamer1.0 \
    ldconfig \
    libegl-mesa \
    libgbm \
    libgles2-mesa \
    libgstallocators-1.0 \
    libgstaudio-1.0 \
    libgstpbutils-1.0 \
    libgsttag-1.0 \
    libgstvideo-1.0 \
    libsecret \
    libsqlite3 \
    libstdc++ \
    libudev \
    libxkbcommon \
    libxml2 \
    mesa-megadriver \
    ttf-bitstream-vera \
    wayland \
    xkeyboard-config \
"
