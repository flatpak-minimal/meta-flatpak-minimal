#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# In the vfpk guest flatpak runs as root under a single init script, with no
# D-Bus and no polkit: as uid 0 it never calls the system helper. Build it
# without the helper so the guest does not need polkit. Scoped to the vfpk
# distro, so other builds are unaffected.
REQUIRED_DISTRO_FEATURES:remove:vfpk = "polkit"
DEPENDS:remove:vfpk = "polkit"
EXTRA_OEMESON:append:vfpk = " -Dsystem_helper=disabled"
