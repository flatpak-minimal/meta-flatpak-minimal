/*
 * SPDX-FileCopyrightText: Copyright (c) 2026 Contributors of meta-flatpak-minimal
 *
 * SPDX-License-Identifier: MIT
 *
 * Prints where it runs, so the output shows it ran in the flatpak sandbox
 * on org.flatpak_minimal.Platform and linked the runtime's GLib.
 */
#include <glib.h>
#include <stdio.h>

int main(void)
{
    const char *id = g_getenv("FLATPAK_ID");

    printf("hello: id=%s glib=%u.%u.%u\n", id ? id : "(not in flatpak)",
           glib_major_version, glib_minor_version, glib_micro_version);
    return id ? 0 : 1;
}
