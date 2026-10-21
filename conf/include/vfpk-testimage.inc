#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Test configuration: flatpak-minimal-image with the vfpk test runtime and
# app installed at build time, booted under testimage. Used by CI; for a
# local run add to local.conf:
#
#   BBMULTICONFIG = "vfpk-<arch>"        # vfpk-aarch64, vfpk-x86-64, ...
#   require conf/include/vfpk-testimage.inc
#
# then: bitbake flatpak-minimal-image -c testimage
#
# Not for products: root logs in without a password, and the test remote is
# unsigned and has no real URL.

# The test refs install under their own unsigned remote.
FLATPAK_BUILD_REMOTE = "vfpk-test"
FLATPAK_REMOTES:append = " vfpk-test"
FLATPAK_REMOTE_URL[vfpk-test] = "https://flatpak.example.invalid/vfpk-test/"
FLATPAK_REMOTE_TITLE[vfpk-test] = "vfpk test content"
FLATPAK_REMOTE_NO_GPG[vfpk-test] = "1"

BUNDLED_FLATPAKS:pn-flatpak-minimal-image = "vfpk-test-hello-flatpak"

# testimage logs in as root over ssh.
IMAGE_FEATURES:append:pn-flatpak-minimal-image = " allow-empty-password empty-root-password allow-root-login"

# testimage boots the image under qemu, so qemu machines need a real kernel
# (CI builds with linux-dummy otherwise). Other machines keep their BSP's.
PREFERRED_PROVIDER_virtual/kernel:qemuall = "linux-yocto"

IMAGE_CLASSES += "testimage"
TEST_SUITES:pn-flatpak-minimal-image = "ping ssh flatpak"
# User-mode networking needs no tap devices or root on the build host.
TEST_RUNQEMUPARAMS = "slirp"
TEST_QEMUPARAMS = "-m 1024"
# KVM only where /dev/kvm is usable; a CI container may not have it.
QEMU_USE_KVM = "${@'1' if os.access('/dev/kvm', os.R_OK | os.W_OK) else ''}"
