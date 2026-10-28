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

FLATPAK_PUBLISH_REPO = "${FLATPAK_DEPLOY_DIR}/repo-dev"
# Developers install the SDK over the network: one delta from scratch per ref
# instead of every object, at about twice the repository's size.
FLATPAK_PUBLISH_DELTAS ?= "previous empty"
# With FLATPAK_PUBLISH_REMOTE_URL set, developers add the repository with
#   flatpak remote-add --user flatpak-minimal-sdk URL/flatpak-minimal-sdk.flatpakrepo
FLATPAK_PUBLISH_REMOTE_NAME ?= "flatpak-minimal-sdk"
FLATPAK_PUBLISH_REMOTE_TITLE ?= "flatpak-minimal SDK"
FLATPAK_PUBLISH_REMOTE_HOMEPAGE ?= "${HOMEPAGE}"

require flatpak-repo-index.inc
