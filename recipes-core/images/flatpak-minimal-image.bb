#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Minimal image with flatpak and the predefined system remotes"
DESCRIPTION = "Reference image for meta-flatpak-minimal. Ships flatpak and \
               the remotes from flatpak-remotes; flatpak apps installed at \
               build time are added by flatpak-cross-install."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

inherit core-image features_check flatpak-cross-install

REQUIRED_DISTRO_FEATURES = "polkit systemd"

IMAGE_FEATURES += "ssh-server-dropbear"

IMAGE_INSTALL += "flatpak flatpak-remotes"
