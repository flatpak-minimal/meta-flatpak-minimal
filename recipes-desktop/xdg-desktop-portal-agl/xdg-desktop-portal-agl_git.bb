#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "xdg-desktop-portal backend for AGL"
DESCRIPTION = "Implements the Screenshot and Settings portal interfaces on top \
of AGL's Wayland compositor. Capture tries weston_capture_v1, then \
agl_screenshooter, then wlr-screencopy."
HOMEPAGE = "https://github.com/flatpak-minimal/xdg-desktop-portal-agl"
BUGTRACKER = "https://github.com/flatpak-minimal/xdg-desktop-portal-agl/issues"

LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://LICENSE;md5=570a9b3749dd0463a1778803b12a6dce"

# Untagged upstream; PV tracks the Cargo.toml version.
PV = "0.1.0+git"
SRCREV = "175ba28c814039d2bc6daa2e8749ba0f3e743a94"
SRC_URI = "git://github.com/flatpak-minimal/xdg-desktop-portal-agl.git;branch=main;protocol=https"

# wayland-sys links libwayland-client through pkg-config. Everything else in
# the tree is pure Rust -- zbus talks the D-Bus wire protocol itself, so
# libdbus is not needed.
DEPENDS = "wayland"

# Both units are user units and the daemon needs a compositor.
REQUIRED_DISTRO_FEATURES = "systemd wayland"

# Cargo.toml sets profile.release.strip = true. A binary that arrives at
# do_package already stripped leaves nothing for the debug split and trips the
# already-stripped QA check, which is fatal by default. Keep the symbols and
# let OE do the stripping into ${PN}-dbg.
export CARGO_PROFILE_RELEASE_STRIP = "false"

inherit cargo cargo-update-recipe-crates pkgconfig features_check

require ${BPN}-crates.inc

# The D-Bus service file and the systemd unit both name /usr/libexec, and
# xdg-desktop-portal expects backends there rather than on PATH.
XDP_AGL_LIBEXEC = "${libexecdir}/${BPN}"

do_install:append() {
    install -d ${D}${libexecdir}
    mv ${D}${bindir}/${BPN} ${D}${XDP_AGL_LIBEXEC}
    rmdir --ignore-fail-on-non-empty ${D}${bindir}

    # Backend registration: which interfaces this backend implements, and
    # which one xdg-desktop-portal picks when XDG_CURRENT_DESKTOP=AGL.
    install -d ${D}${datadir}/xdg-desktop-portal/portals
    install -m 0644 ${S}/data/agl.portal \
        ${D}${datadir}/xdg-desktop-portal/portals/agl.portal
    install -m 0644 ${S}/data/agl-portals.conf \
        ${D}${datadir}/xdg-desktop-portal/agl-portals.conf

    install -d ${D}${datadir}/dbus-1/services
    install -m 0644 ${S}/data/org.freedesktop.impl.portal.desktop.agl.service \
        ${D}${datadir}/dbus-1/services/

    install -d ${D}${systemd_user_unitdir}
    install -m 0644 ${S}/data/xdg-desktop-portal-agl.service.in \
        ${D}${systemd_user_unitdir}/xdg-desktop-portal-agl.service
    install -m 0644 ${S}/data/weston-environment.service \
        ${D}${systemd_user_unitdir}/

    # Upstream hardcodes /usr/libexec in both files; rewrite so a build with a
    # non-default libexecdir still points at the installed binary.
    sed -i -e 's,/usr/libexec/${BPN},${XDP_AGL_LIBEXEC},g' \
        ${D}${datadir}/dbus-1/services/org.freedesktop.impl.portal.desktop.agl.service \
        ${D}${systemd_user_unitdir}/xdg-desktop-portal-agl.service

    # weston-environment.service is not D-Bus activated, so it has to be
    # wanted by something. The portal backend itself is Type=dbus and is
    # started on demand by the service file above.
    #
    # Note the unit waits on /run/user/1000/wayland-1 -- upstream hardcodes
    # both the uid and the display name. On a target whose session user is not
    # 1000 it times out and the session environment is never published, which
    # shows up as the portal falling back to a non-AGL backend.
    install -d ${D}${systemd_user_unitdir}/default.target.wants
    ln -sf ../weston-environment.service \
        ${D}${systemd_user_unitdir}/default.target.wants/weston-environment.service

    # Sourced, not executed: exports XDG_CURRENT_DESKTOP=AGL and the session
    # bus address for shells that start outside the systemd user session.
    install -d ${D}${sysconfdir}/profile.d
    install -m 0644 ${S}/data/agl-portal.sh ${D}${sysconfdir}/profile.d/
}

# ${libexecdir}/* and ${datadir}/${BPN} are already in the default FILES:${PN}.
FILES:${PN} += " \
    ${datadir}/xdg-desktop-portal \
    ${datadir}/dbus-1/services \
    ${systemd_user_unitdir} \
"

RDEPENDS:${PN} = "xdg-desktop-portal"
