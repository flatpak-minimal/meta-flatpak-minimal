#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Kernel options for the vfpk guest. Scoped to the vfpk distro, so other
# builds are unaffected.
FILESEXTRAPATHS:prepend:vfpk := "${THISDIR}/files:"
SRC_URI:append:vfpk = " file://vfpk-guest.cfg"
