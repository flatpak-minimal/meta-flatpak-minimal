# SPDX-FileCopyrightText: Copyright (c) 2026 Contributors of meta-flatpak-minimal
#
# SPDX-License-Identifier: MIT
#

project('hello', 'c', version: '1.0', default_options: ['warning_level=3'])

glib = dependency('glib-2.0')
executable('hello', 'hello.c', dependencies: glib, install: true)
