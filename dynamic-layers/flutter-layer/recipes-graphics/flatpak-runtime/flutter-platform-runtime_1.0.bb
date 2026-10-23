#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Flutter flatpak runtime, packaged for build-time install"
DESCRIPTION = "The org.flatpak_minimal.Flutter.Platform runtime from \
               flutter-platform-runtime-image, in the form \
               flatpak-cross-install installs at build time."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

# Every license of every package the runtime image installs. The image is a
# Yocto rootfs, so this follows whatever oe-core and meta-openembedded ship;
# do_compile checks it against the image's deployed list and prints the
# corrected line when they drift, so regenerate it from that.
LICENSE = "0BSD & Apache-2.0 & BSD-1-Clause & BSD-2-Clause & BSD-3-Clause & \
           Bitstream-Vera & FTL & GCC-exception-3.1 & GCR-docs & \
           GPL-2.0-only & GPL-2.0-or-later & GPL-3.0-only & \
           GPL-3.0-or-later & HPND & HPND-sell-variant & IJG & ISC & \
           LGPL-2.0-only & LGPL-2.0-or-later & LGPL-2.1-only & \
           LGPL-2.1-or-later & LGPL-3.0-only & LGPL-3.0-or-later & \
           LLVM-exception & Libpng & LicenseRef-PD & MIT & MIT-open-group & \
           MPL-2.0 & Unicode-DFS-2016 & X11 & Zlib & blessing & \
           bzip2-1.0.6 & curl"

inherit flatpak-bundle

FLATPAK_IMAGE = "flutter-platform-runtime-image"
