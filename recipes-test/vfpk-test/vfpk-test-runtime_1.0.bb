#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Minimal flatpak runtime for testing vfpk, packaged"
DESCRIPTION = "The org.flatpak_minimal.Test.Platform runtime from \
               vfpk-test-runtime-image, in the form flatpak-cross-install \
               installs at build time."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

# The licenses of the packages in the runtime; do_compile checks the list.
VFPK_TEST_RUNTIME_LICENSES = "GPL-2.0-only GPL-2.0-or-later LGPL-2.1-or-later bzip2-1.0.6"
# meta-selinux links busybox to libselinux when the target enables SELinux.
# The runtime is built in the target configuration, not the vfpk guest.
VFPK_TEST_RUNTIME_LICENSES:append = "${@bb.utils.contains('DISTRO_FEATURES', 'selinux', ' PD', '', d)}"
LICENSE = "${@flatpak_license(d, d.getVar('VFPK_TEST_RUNTIME_LICENSES'))}"

inherit flatpak-bundle

FLATPAK_IMAGE = "vfpk-test-runtime-image"
