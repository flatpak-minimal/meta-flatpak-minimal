#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# vfpk-testimage.inc with the test content in a user installation: seeded
# into the home of a test account on first boot, and tested as that account.
# For a local run add to local.conf:
#
#   BBMULTICONFIG = "vfpk-<arch>"        # vfpk-aarch64, vfpk-x86-64, ...
#   require conf/include/vfpk-testimage-user.inc
#
# then: bitbake flatpak-minimal-image -c testimage
#
# Not for products, for the reasons in vfpk-testimage.inc.

require conf/include/vfpk-testimage.inc

IMAGE_CLASSES += "extrausers"
EXTRA_USERS_PARAMS:pn-flatpak-minimal-image = "useradd -m -u 1100 -s /bin/sh vfpktest;"

FLATPAK_INSTALL_SCOPE:pn-flatpak-minimal-image = "user"
FLATPAK_INSTALL_USER:pn-flatpak-minimal-image = "vfpktest"
FLATPAK_DEPLOY_MODE:pn-flatpak-minimal-image = "seed"
