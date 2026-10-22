#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Developer flatpak repository of the refs this build produced"
DESCRIPTION = "Like flatpak-repo-index, but into ${DEPLOY_DIR}/flatpak/repo-dev \
               and with the SDKs: what flatpak-builder needs to build apps \
               for the runtimes built here. Publish it apart from the \
               repository devices update from."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

FLATPAK_PUBLISH_REPO = "${DEPLOY_DIR}/flatpak/repo-dev"

require flatpak-repo-index.inc
