#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Base flatpak runtime, packaged for build-time install"
DESCRIPTION = "The org.flatpak_minimal.Platform runtime from \
               flatpak-platform-runtime-image, in the form \
               flatpak-cross-install installs at build time."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "Apache-2.0 & BSD-1-Clause & BSD-2-Clause & BSD-3-Clause & Bitstream-Vera & FTL & \
           GCR-docs & GPL-2.0-only & GPL-2.0-or-later & GPL-3.0-with-GCC-exception & HPND & \
           HPND-sell-variant & ISC & LGPL-2.0-or-later & LGPL-2.1-only & LGPL-2.1-or-later & \
           Libpng & MIT & MIT-open-group & MPL-2.0 & PD & X11 & Zlib & blessing & bzip2-1.0.6"

inherit flatpak-bundle

FLATPAK_IMAGE = "flatpak-platform-runtime-image"
