#!/bin/sh
# SPDX-FileCopyrightText: Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#
# Prints who and where it runs, so a test can tell it ran inside flatpak.
echo "vfpk-test-hello: id=${FLATPAK_ID:-none} arch=$(uname -m)"
