#
# Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
SUMMARY = "OpenPGP signature verification for ostree and flatpak, on Sequoia"
DESCRIPTION = "What libostree and flatpak ask of GPGME and gpg, done with \
               the Sequoia OpenPGP library: checking signatures against the \
               keyrings of a remote, and importing keys into one. With it a \
               device verifies pulls from a GPG-signed remote, Flathub among \
               them, with neither GnuPG nor GPGME installed. See \
               FLATPAK_OPENPGP."
HOMEPAGE = "https://github.com/flatpak-minimal/meta-flatpak-minimal"

# The library's own license, then those of the crates linked into it, as
# 'cargo metadata' gives them. Sequoia is built on OpenSSL: its default,
# Nettle, is LGPL-3.0-or-later or GPL-2.0-or-later.
LICENSE = "LGPL-2.0-or-later & Apache-2.0 & BSD-3-Clause & BSL-1.0 & MIT & Unicode-3.0 & Zlib \
    & (Apache-2.0 | MIT) & (MIT | Unlicense)"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/LGPL-2.0-or-later;md5=6d2d9952d88b50a51a5c73dc431d06c7"

DEPENDS = "openssl"

inherit pkgconfig cargo cargo-update-recipe-crates

SRC_URI = "file://openpgp-verify-sequoia"
require ${BPN}-crates.inc

S = "${UNPACKDIR}/openpgp-verify-sequoia"

CARGO_INSTALL_LIBRARIES = "1"

do_install:append () {
	# cargo installs the library under rustlibdir, without its soname.
	install -d ${D}${libdir}/pkgconfig ${D}${includedir}
	mv ${D}${rustlibdir}/libopenpgp_verify_sequoia.so ${D}${libdir}/libopenpgp_verify_sequoia.so.0
	ln -s libopenpgp_verify_sequoia.so.0 ${D}${libdir}/libopenpgp_verify_sequoia.so
	rmdir -p --ignore-fail-on-non-empty ${D}${rustlibdir}

	install -m 0644 ${S}/include/openpgp-verify-sequoia.h ${D}${includedir}/
	cat > ${D}${libdir}/pkgconfig/openpgp-verify-sequoia.pc <<-EOF
		prefix=${prefix}
		libdir=${libdir}
		includedir=${includedir}

		Name: openpgp-verify-sequoia
		Description: OpenPGP signature verification for ostree and flatpak, on Sequoia
		Version: ${PV}
		Libs: -L${libdir} -lopenpgp_verify_sequoia
		Cflags: -I${includedir}
	EOF
}
