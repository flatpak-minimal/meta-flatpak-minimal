#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Deploy the flatpak refs a recipe produces, for publishing.
#
# Each producer (flatpak-runtime-image, flatpak-app) puts an ostree archive
# repository holding its refs in ${FLATPAK_DEPLOYDIR}/repo, and
# do_deploy_flatpak deploys it, through sstate, to
#
#   ${FLATPAK_DEPLOY_DIR}/refs/${FLATPAK_DEPLOY_ARCH}/${PN}/
#
# which is ${DEPLOY_DIR}/flatpak/refs/${PACKAGE_ARCH}/${PN}/ unless a
# multiconfig says otherwise (flatpak-common).
#
# A flatpak repository is a feed, like deploy/ipk, not a per-machine image
# artifact: refs are named by flatpak arch and one repository carries all of
# them. The package arch in the path keeps two machines, or two CPU tunes,
# that build the same recipe from colliding; flatpak-repo-index merges every
# producer's refs into the publishable ${DEPLOY_DIR}/flatpak/repo and refuses
# two different commits of one ref.

inherit flatpak-common

FLATPAK_DEPLOY_REFS_DIR = "${FLATPAK_DEPLOY_DIR}/refs"
FLATPAK_DEPLOYDIR = "${WORKDIR}/deploy-flatpak"

SSTATETASKS += "do_deploy_flatpak"
do_deploy_flatpak[sstate-inputdirs] = "${FLATPAK_DEPLOYDIR}"
do_deploy_flatpak[sstate-outputdirs] = "${FLATPAK_DEPLOY_REFS_DIR}/${FLATPAK_DEPLOY_ARCH}/${PN}"

python do_deploy_flatpak_setscene () {
    sstate_setscene(d)
}
addtask do_deploy_flatpak_setscene
