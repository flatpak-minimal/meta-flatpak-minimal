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

LICENSE = "0BSD & Apache-2.0 & BSD-1-Clause & BSD-2-Clause & BSD-3-Clause & \
           Bitstream-Vera & FTL & GCR-docs & GPL-2.0-only & \
           GPL-2.0-or-later & GPL-3.0-only & GPL-3.0-or-later & \
           GPL-3.0-or-later WITH GCC-exception-3.1 & HPND & \
           HPND-sell-variant & IJG & ISC & LGPL-2.0-only & \
           LGPL-2.0-or-later & LGPL-2.1-only & LGPL-2.1-or-later & \
           LGPL-3.0-only & LGPL-3.0-or-later & Libpng & LicenseRef-PD & \
           MIT & MIT-open-group & MPL-2.0 & Unicode-DFS-2016 & X11 & Zlib & \
           blessing & bzip2-1.0.6 & curl"

# x86-64 mesa builds the LLVM-backed gallium drivers, so mesa-megadriver
# pulls libllvm into the runtime and the runtime carries its exception. No
# other arch does, and naming it unconditionally warns there instead.
LICENSE:append:x86-64 = " & Apache-2.0 WITH LLVM-exception"

inherit flatpak-bundle

FLATPAK_IMAGE = "flatpak-platform-runtime-image"
