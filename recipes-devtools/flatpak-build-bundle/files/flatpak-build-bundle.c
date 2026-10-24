/*
 * Copyright (c) 2026 Contributors of meta-flatpak-minimal
 *
 * SPDX-License-Identifier: MIT
 *
 * Write a single-file flatpak bundle of one ref, as 'flatpak build-bundle'
 * does, with libostree alone:
 *
 *   flatpak-build-bundle --repo=REPO --ref=REF [--origin=URL]
 *                        [--gpg-keys=FILE] [--timestamp=SECONDS] OUTPUT
 *
 * A bundle is an ostree static delta from nothing to the ref's commit, with
 * every part inline, whose metadata carries the "flatpak" header, the ref,
 * the ref's metadata keyfile and, optionally, the remote it updates from
 * (--origin) and the keys that remote signs with (--gpg-keys, binary).
 * 'flatpak install --bundle' reads it.
 *
 * ostree stamps the delta with the current time. --timestamp rewrites that
 * field, so the same commit gives the same bundle.
 */

#include <errno.h>
#include <stdio.h>
#include <unistd.h>

#include <ostree.h>

/* ostree-repo-static-delta-private.h; flatpak reads bundles as this. */
#define SUPERBLOCK_FORMAT "(a{sv}tayay(a{sv}aya(say)sstayay)aya(uayttay)a(yaytt))"
/* "flatpak", then a byte-order check and format version 1 (flatpak). */
#define BUNDLE_MAGIC 0xe5890001

static char *opt_repo;
static char *opt_ref;
static char *opt_origin;
static char *opt_gpg_keys;
static gint64 opt_timestamp = -1;

static GOptionEntry entries[] = {
  { "repo", 0, 0, G_OPTION_ARG_FILENAME, &opt_repo, "Repository holding the ref", "REPO" },
  { "ref", 0, 0, G_OPTION_ARG_STRING, &opt_ref, "Full ref, e.g. runtime/ID/ARCH/BRANCH", "REF" },
  { "origin", 0, 0, G_OPTION_ARG_STRING, &opt_origin, "URL of the remote the ref updates from", "URL" },
  { "gpg-keys", 0, 0, G_OPTION_ARG_FILENAME, &opt_gpg_keys, "Binary keyring of the remote", "FILE" },
  { "timestamp", 0, 0, G_OPTION_ARG_INT64, &opt_timestamp, "Delta timestamp, seconds since the epoch", "SECONDS" },
  { NULL }
};

static gboolean
set_timestamp (const char *path, guint64 timestamp, GError **error)
{
  g_autoptr(GMappedFile) mapped = NULL;
  g_autoptr(GBytes) bytes = NULL;
  g_autoptr(GVariant) superblock = NULL;
  g_autoptr(GVariant) rewritten = NULL;
  GVariant **children;
  gsize n, i;

  mapped = g_mapped_file_new (path, FALSE, error);
  if (mapped == NULL)
    return FALSE;
  bytes = g_mapped_file_get_bytes (mapped);
  superblock = g_variant_ref_sink (g_variant_new_from_bytes (G_VARIANT_TYPE (SUPERBLOCK_FORMAT),
                                                             bytes, FALSE));
  if (!g_variant_is_normal_form (superblock))
    {
      g_set_error (error, G_IO_ERROR, G_IO_ERROR_INVALID_DATA, "%s is not a static delta superblock", path);
      return FALSE;
    }

  /* The timestamp is fixed-size, so every other byte stays where it was. */
  n = g_variant_n_children (superblock);
  children = g_new (GVariant *, n);
  for (i = 0; i < n; i++)
    children[i] = i == 1 ? g_variant_new_uint64 (GUINT64_TO_BE (timestamp))
                         : g_variant_get_child_value (superblock, i);
  rewritten = g_variant_ref_sink (g_variant_new_tuple (children, n));
  g_free (children);

  return g_file_set_contents (path, g_variant_get_data (rewritten), g_variant_get_size (rewritten), error);
}

int
main (int argc, char **argv)
{
  g_autoptr(GOptionContext) context = NULL;
  g_autoptr(GError) error = NULL;
  g_autoptr(GFile) repo_path = NULL;
  g_autoptr(OstreeRepo) repo = NULL;
  g_autoptr(GFile) root = NULL;
  g_autoptr(GFile) metadata_file = NULL;
  g_autofree char *checksum = NULL;
  g_autofree char *metadata = NULL;
  g_autofree char *gpg_data = NULL;
  g_autofree char *tmp = NULL;
  gsize gpg_len = 0;
  const char *collection_id;
  GVariantBuilder meta;
  GVariantBuilder params;
  g_autoptr(GVariant) meta_v = NULL;
  g_autoptr(GVariant) params_v = NULL;

  context = g_option_context_new ("OUTPUT - write a flatpak bundle of a ref");
  g_option_context_add_main_entries (context, entries, NULL);
  if (!g_option_context_parse (context, &argc, &argv, &error))
    goto fail;
  if (argc != 2 || opt_repo == NULL || opt_ref == NULL)
    {
      g_printerr ("usage: %s --repo=REPO --ref=REF [--origin=URL] [--gpg-keys=FILE] "
                  "[--timestamp=SECONDS] OUTPUT\n", g_get_prgname ());
      return 2;
    }

  repo_path = g_file_new_for_path (opt_repo);
  repo = ostree_repo_new (repo_path);
  if (!ostree_repo_open (repo, NULL, &error))
    goto fail;
  if (!ostree_repo_resolve_rev (repo, opt_ref, FALSE, &checksum, &error))
    goto fail;
  if (!ostree_repo_read_commit (repo, checksum, &root, NULL, NULL, &error))
    goto fail;
  metadata_file = g_file_resolve_relative_path (root, "metadata");
  if (!g_file_load_contents (metadata_file, NULL, &metadata, NULL, NULL, &error))
    goto fail;
  if (opt_gpg_keys && !g_file_get_contents (opt_gpg_keys, &gpg_data, &gpg_len, &error))
    goto fail;

  /* Added first, so the header leads the file. */
  g_variant_builder_init (&meta, G_VARIANT_TYPE ("a{sv}"));
  g_variant_builder_add (&meta, "{sv}", "flatpak", g_variant_new_uint32 (BUNDLE_MAGIC));
  g_variant_builder_add (&meta, "{sv}", "ref", g_variant_new_string (opt_ref));
  g_variant_builder_add (&meta, "{sv}", "metadata", g_variant_new_string (metadata));
  if (opt_origin)
    g_variant_builder_add (&meta, "{sv}", "origin", g_variant_new_string (opt_origin));
  collection_id = ostree_repo_get_collection_id (repo);
  g_variant_builder_add (&meta, "{sv}", "collection-id",
                         g_variant_new_string (collection_id ? collection_id : ""));
  if (gpg_data)
    g_variant_builder_add (&meta, "{sv}", "gpg-keys",
                           g_variant_new_fixed_array (G_VARIANT_TYPE_BYTE, gpg_data, gpg_len, 1));
  meta_v = g_variant_ref_sink (g_variant_builder_end (&meta));

  /* Written beside OUTPUT, then renamed: a failed run leaves no bundle. */
  tmp = g_strconcat (argv[1], ".tmp", NULL);
  g_variant_builder_init (&params, G_VARIANT_TYPE ("a{sv}"));
  g_variant_builder_add (&params, "{sv}", "min-fallback-size", g_variant_new_uint32 (0));
  g_variant_builder_add (&params, "{sv}", "compression", g_variant_new_byte ('x'));
  g_variant_builder_add (&params, "{sv}", "bsdiff-enabled", g_variant_new_boolean (FALSE));
  g_variant_builder_add (&params, "{sv}", "inline-parts", g_variant_new_boolean (TRUE));
  g_variant_builder_add (&params, "{sv}", "include-detached", g_variant_new_boolean (TRUE));
  g_variant_builder_add (&params, "{sv}", "filename", g_variant_new_bytestring (tmp));
  params_v = g_variant_ref_sink (g_variant_builder_end (&params));

  if (!ostree_repo_static_delta_generate (repo, OSTREE_STATIC_DELTA_GENERATE_OPT_LOWLATENCY,
                                          NULL, checksum, meta_v, params_v, NULL, &error))
    goto fail;
  if (opt_timestamp >= 0 && !set_timestamp (tmp, (guint64) opt_timestamp, &error))
    goto fail;
  if (rename (tmp, argv[1]) != 0)
    {
      g_set_error (&error, G_IO_ERROR, g_io_error_from_errno (errno), "rename %s: %s", tmp, g_strerror (errno));
      goto fail;
    }
  return 0;

fail:
  if (tmp)
    unlink (tmp);
  g_printerr ("flatpak-build-bundle: %s\n", error->message);
  return 1;
}
