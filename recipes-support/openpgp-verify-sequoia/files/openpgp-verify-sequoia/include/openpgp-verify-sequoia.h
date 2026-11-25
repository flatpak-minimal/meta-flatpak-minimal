/* SPDX-License-Identifier: LGPL-2.0-or-later */
/*
 * OpenPGP signature verification and keyring handling for libostree and
 * flatpak, on Sequoia. It does what they asked of GPGME and gpg: check
 * signatures against a set of keyrings, and merge keys into a keyring.
 *
 * Every function returns 0 on success. On failure it returns -1 and, when
 * ERROR is not NULL, stores a message there; free it with
 * opv_string_free().
 */
#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct
{
  const uint8_t *data;
  size_t len;
} OpvBuffer;

/* One signature of a detached signature blob, as gpg would report it. */
typedef struct
{
  /* Good, from a key in the keyrings that is neither expired nor revoked. */
  uint8_t valid;
  uint8_t sig_expired;
  uint8_t key_expired;
  uint8_t key_revoked;
  uint8_t key_missing;
  /* Unix timestamps; an expiration of 0 means none. */
  int64_t timestamp;
  int64_t exp_timestamp;
  int64_t key_exp_timestamp;
  int64_t key_exp_timestamp_primary;
  /* Of the signing key or subkey; the issuer's ID when the key is missing. */
  char *fingerprint;
  /* Empty when the key is missing. */
  char *fingerprint_primary;
  char *pubkey_algo_name;
  char *hash_algo_name;
  /* Of the certificate's primary user ID; NULL when unknown. */
  char *user_name;
  char *user_email;
  /* Every key and subkey of the signing certificate, space-separated. */
  char *cert_fingerprints;
} OpvSignature;

/*
 * Check the detached signatures in SIGNATURES over DATA against the
 * certificates in KEYRINGS. Each keyring is binary or ASCII-armored. A
 * signature that does not verify is not an error: it is reported with valid
 * unset. Free the result with opv_signatures_free().
 */
int opv_verify (const OpvBuffer *keyrings, size_t n_keyrings,
                   const uint8_t *data, size_t data_len,
                   const uint8_t *signatures, size_t signatures_len,
                   OpvSignature **out_signatures, size_t *out_n_signatures,
                   char **error);

/*
 * Check MESSAGE, an OpenPGP message that carries its signatures with its
 * content (gpg --sign), against the certificates in KEYRINGS, and return
 * the signatures as opv_verify() does. The content is returned only when
 * at least one signature is valid; otherwise OUT_CONTENT is NULL. Free it
 * with opv_bytes_free().
 */
int opv_verify_message (const OpvBuffer *keyrings, size_t n_keyrings,
                        const uint8_t *message, size_t message_len,
                        OpvSignature **out_signatures, size_t *out_n_signatures,
                        uint8_t **out_content, size_t *out_content_len,
                        char **error);

void opv_signatures_free (OpvSignature *signatures, size_t n_signatures);

/*
 * Merge certificates from SOURCE (binary or ASCII-armored) into KEYRING
 * (binary, may be empty) and return the new binary keyring. KEY_IDS, a
 * NULL-terminated array of key IDs or fingerprints, restricts which
 * certificates are taken; NULL takes all. OUT_IMPORTED is the number of
 * certificates the keyring did not have before. Free the keyring with
 * opv_bytes_free().
 */
int opv_keyring_import (const uint8_t *keyring, size_t keyring_len,
                           const uint8_t *source, size_t source_len,
                           const char *const *key_ids,
                           uint8_t **out_keyring, size_t *out_keyring_len,
                           unsigned int *out_imported,
                           char **error);

void opv_bytes_free (uint8_t *bytes, size_t len);
void opv_string_free (char *string);

#ifdef __cplusplus
}
#endif
