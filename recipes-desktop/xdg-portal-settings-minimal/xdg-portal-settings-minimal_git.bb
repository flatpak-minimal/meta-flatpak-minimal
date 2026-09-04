#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "Minimal org.freedesktop.impl.portal.Settings implementation"
DESCRIPTION = "D-Bus service implementing the XDG Desktop Portal Settings \
interface, with type checking on updates and namespace filtering on reads. \
Ships the service and a client that exercises every documented setting."
HOMEPAGE = "https://github.com/flatpak-minimal/xdg-portal-settings-minimal"
BUGTRACKER = "https://github.com/flatpak-minimal/xdg-portal-settings-minimal/issues"

# Upstream is inconsistent: the LICENSE file is Apache-2.0 while Cargo.toml and
# README.md say MIT. Follow the LICENSE file, which is what the checksum below
# covers. Worth resolving upstream.
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=86d3f3a95c324c9479bd8986968f4327"

# Untagged upstream; PV tracks the workspace version.
PV = "0.1.0+git"
SRCREV = "3f0d8bce8860b01cb7eee523859b0a3216cdc6d0"
SRC_URI = "git://github.com/flatpak-minimal/xdg-portal-settings-minimal.git;branch=main;protocol=https"

# Pure Rust: zbus speaks the D-Bus wire protocol directly, so there is no
# libdbus to link against.

inherit cargo cargo-update-recipe-crates

require ${BPN}-crates.inc

# Upstream ships no D-Bus service file and no systemd unit, so nothing starts
# this automatically. It has to be launched by the session, and it claims
# org.freedesktop.impl.portal.Settings directly -- it cannot run alongside
# another backend that owns the same name (xdg-desktop-portal-agl does).
# The client is a test harness, not part of the service. Split it out so an
# image can install the portal without it.
PACKAGE_BEFORE_PN += "${PN}-client"

FILES:${PN}-client = "${bindir}/portal-setting-client"
SUMMARY:${PN}-client = "Test client for the minimal Settings portal"

RDEPENDS:${PN}-client = "${PN}"
