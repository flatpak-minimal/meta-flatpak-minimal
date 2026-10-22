#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Publishable flatpak repository of the refs this build produced"
DESCRIPTION = "Merges the refs every flatpak producer deployed under \
               ${DEPLOY_DIR}/flatpak/refs into one ostree repository, \
               ${DEPLOY_DIR}/flatpak/repo, ready to sync to the remote \
               devices update from. The flatpak counterpart of package-index: \
               build the producers, then run it. SDKs go to the developer \
               repository, flatpak-repo-index-dev, not here."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

LICENSE = "MIT"

FLATPAK_PUBLISH_REPO = "${DEPLOY_DIR}/flatpak/repo"
# Devices never need an SDK or its extensions.
FLATPAK_PUBLISH_EXCLUDE ?= "runtime/[^/]+[.]Sdk([.][^/]+)?/.+"

require flatpak-repo-index.inc
