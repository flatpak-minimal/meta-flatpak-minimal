// SPDX-License-Identifier: LGPL-2.0-or-later
//
// OpenPGP signature verification and keyring handling for libostree and
// flatpak, on Sequoia. See include/openpgp-verify-sequoia.h for the
// interface.
//
// Both used GPGME for this, which runs gpg. The results here are meant to
// match what gpg reported, so that their callers see no change:
// in particular a good signature counts only while its key and certificate
// are, at the time of the check, neither expired nor revoked. Sequoia by
// itself asks only that the key was valid when the signature was made.

use std::ffi::{c_char, c_int, c_uint, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Context, Result};
use sequoia_openpgp as openpgp;

use openpgp::cert::prelude::*;
use openpgp::packet::Signature;
use openpgp::parse::stream::{
    DetachedVerifierBuilder, GoodChecksum, MessageLayer, MessageStructure, VerificationError,
    VerificationHelper, VerifierBuilder,
};
use openpgp::parse::Parse;
use openpgp::policy::{Policy, StandardPolicy};
use openpgp::serialize::Serialize;
use openpgp::types::{HashAlgorithm, PublicKeyAlgorithm, RevocationStatus};
use openpgp::{Cert, Fingerprint, KeyHandle};

#[repr(C)]
pub struct OpvBuffer {
    data: *const u8,
    len: usize,
}

#[repr(C)]
pub struct OpvSignature {
    valid: u8,
    sig_expired: u8,
    key_expired: u8,
    key_revoked: u8,
    key_missing: u8,
    timestamp: i64,
    exp_timestamp: i64,
    key_exp_timestamp: i64,
    key_exp_timestamp_primary: i64,
    fingerprint: *mut c_char,
    fingerprint_primary: *mut c_char,
    pubkey_algo_name: *mut c_char,
    hash_algo_name: *mut c_char,
    user_name: *mut c_char,
    user_email: *mut c_char,
    cert_fingerprints: *mut c_char,
}

/// One signature, before it is handed to C.
#[derive(Default)]
struct SigInfo {
    valid: bool,
    sig_expired: bool,
    key_expired: bool,
    key_revoked: bool,
    key_missing: bool,
    timestamp: i64,
    exp_timestamp: i64,
    key_exp_timestamp: i64,
    key_exp_timestamp_primary: i64,
    fingerprint: String,
    fingerprint_primary: String,
    pubkey_algo_name: String,
    hash_algo_name: String,
    user_name: Option<String>,
    user_email: Option<String>,
    cert_fingerprints: String,
}

fn unix(t: SystemTime) -> i64 {
    match t.duration_since(UNIX_EPOCH) {
        Ok(d) => d.as_secs() as i64,
        Err(_) => 0,
    }
}

fn hex(fpr: &Fingerprint) -> String {
    format!("{:X}", fpr)
}

// The names gpgme_pubkey_algo_name() and gpgme_hash_algo_name() give.
#[allow(deprecated)]
fn pubkey_algo_name(algo: PublicKeyAlgorithm) -> String {
    match algo {
        PublicKeyAlgorithm::RSAEncryptSign
        | PublicKeyAlgorithm::RSAEncrypt
        | PublicKeyAlgorithm::RSASign => "RSA".into(),
        PublicKeyAlgorithm::DSA => "DSA".into(),
        PublicKeyAlgorithm::ECDSA => "ECDSA".into(),
        PublicKeyAlgorithm::ECDH => "ECDH".into(),
        PublicKeyAlgorithm::EdDSA | PublicKeyAlgorithm::Ed25519 | PublicKeyAlgorithm::Ed448 => {
            "EdDSA".into()
        }
        PublicKeyAlgorithm::ElGamalEncrypt | PublicKeyAlgorithm::ElGamalEncryptSign => {
            "ELG-E".into()
        }
        other => other.to_string(),
    }
}

#[allow(deprecated)]
fn hash_algo_name(algo: HashAlgorithm) -> String {
    match algo {
        HashAlgorithm::MD5 => "MD5".into(),
        HashAlgorithm::SHA1 => "SHA1".into(),
        HashAlgorithm::RipeMD => "RIPEMD160".into(),
        HashAlgorithm::SHA224 => "SHA224".into(),
        HashAlgorithm::SHA256 => "SHA256".into(),
        HashAlgorithm::SHA384 => "SHA384".into(),
        HashAlgorithm::SHA512 => "SHA512".into(),
        other => other.to_string(),
    }
}

/// Certificates of a keyring. gpg skips what it cannot read; so does this.
fn parse_certs(data: &[u8]) -> Vec<Cert> {
    if data.is_empty() {
        return Vec::new();
    }
    match CertParser::from_bytes(data) {
        Ok(parser) => parser.filter_map(|c| c.ok()).collect(),
        Err(_) => Vec::new(),
    }
}

fn from_signature(info: &mut SigInfo, sig: &Signature, now: SystemTime) {
    info.pubkey_algo_name = pubkey_algo_name(sig.pk_algo());
    info.hash_algo_name = hash_algo_name(sig.hash_algo());
    if let Some(t) = sig.signature_creation_time() {
        info.timestamp = unix(t);
    }
    if let Some(t) = sig.signature_expiration_time() {
        info.exp_timestamp = unix(t);
        info.sig_expired = t <= now;
    }
    // Replaced by the key's fingerprint once the key is known.
    info.fingerprint = match sig.get_issuers().into_iter().next() {
        Some(KeyHandle::Fingerprint(f)) => hex(&f),
        Some(KeyHandle::KeyID(id)) => format!("{:X}", id),
        None => String::new(),
    };
}

/// What gpg would say of the certificate and of its key FPR right now.
/// Returns whether the policy takes the certificate and that key at all
/// now: Sequoia has only said so for the time the signature was made.
fn from_cert(info: &mut SigInfo, policy: &dyn Policy, cert: &Cert, fpr: &Fingerprint, now: SystemTime) -> bool {
    let mut usable = false;
    info.fingerprint = hex(fpr);
    info.fingerprint_primary = hex(&cert.fingerprint());
    info.cert_fingerprints = cert
        .keys()
        .map(|k| hex(&k.key().fingerprint()))
        .collect::<Vec<_>>()
        .join(" ");

    if let RevocationStatus::Revoked(_) = cert.revocation_status(policy, now) {
        info.key_revoked = true;
    }

    let userid = match cert.with_policy(policy, now) {
        Ok(valid) => {
            if let Some(t) = valid.primary_key().key_expiration_time() {
                info.key_exp_timestamp_primary = unix(t);
            }
            if valid.alive().is_err() {
                info.key_expired = true;
            }
            for key in valid.keys() {
                if &key.key().fingerprint() != fpr {
                    continue;
                }
                usable = true;
                if let Some(t) = key.key_expiration_time() {
                    info.key_exp_timestamp = unix(t);
                }
                if key.alive().is_err() {
                    info.key_expired = true;
                }
                if let RevocationStatus::Revoked(_) = key.revocation_status() {
                    info.key_revoked = true;
                }
            }
            valid.primary_userid().ok().map(|u| u.userid().clone())
        }
        Err(_) => None,
    };
    let userid = userid.or_else(|| cert.userids().next().map(|u| u.userid().clone()));
    if let Some(userid) = userid {
        info.user_name = userid.name().ok().flatten().map(|s| s.to_string());
        info.user_email = userid.email().ok().flatten().map(|s| s.to_string());
    }
    usable
}

struct Helper<'a> {
    policy: &'a dyn Policy,
    certs: Vec<Cert>,
    now: SystemTime,
    signatures: Vec<SigInfo>,
}

impl VerificationHelper for Helper<'_> {
    fn get_certs(&mut self, _ids: &[KeyHandle]) -> openpgp::Result<Vec<Cert>> {
        Ok(self.certs.clone())
    }

    fn check(&mut self, structure: MessageStructure) -> openpgp::Result<()> {
        for layer in structure.into_iter() {
            let results = match layer {
                MessageLayer::SignatureGroup { results } => results,
                _ => continue,
            };
            for result in results {
                let mut info = SigInfo::default();
                match result {
                    Ok(GoodChecksum { sig, ka, .. }) => {
                        from_signature(&mut info, sig, self.now);
                        let usable = from_cert(&mut info, self.policy, ka.cert(), &ka.key().fingerprint(), self.now);
                        info.valid = usable && !info.sig_expired && !info.key_expired && !info.key_revoked;
                    }
                    Err(VerificationError::MissingKey { sig, .. }) => {
                        from_signature(&mut info, sig, self.now);
                        info.key_missing = true;
                    }
                    Err(VerificationError::UnboundKey { sig, cert, .. }) => {
                        from_signature(&mut info, sig, self.now);
                        // The key that made it, if the certificate has it at all.
                        let issuers = sig.get_issuers();
                        let fpr = cert
                            .keys()
                            .map(|k| k.key().fingerprint())
                            .find(|f| issuers.iter().any(|i| i.aliases(KeyHandle::from(f.clone()))))
                            .unwrap_or_else(|| cert.fingerprint());
                        from_cert(&mut info, self.policy, cert, &fpr, self.now);
                    }
                    Err(VerificationError::BadKey { sig, ka, .. })
                    | Err(VerificationError::BadSignature { sig, ka, .. }) => {
                        from_signature(&mut info, sig, self.now);
                        from_cert(&mut info, self.policy, ka.cert(), &ka.key().fingerprint(), self.now);
                    }
                    Err(VerificationError::MalformedSignature { sig, .. }) => {
                        from_signature(&mut info, sig, self.now);
                    }
                    // Reported, and not valid.
                    Err(_) => {}
                }
                self.signatures.push(info);
            }
        }
        // Not an error: the caller decides what an invalid signature means.
        Ok(())
    }
}

fn verify(keyrings: &[&[u8]], data: &[u8], signatures: &[u8]) -> Result<Vec<SigInfo>> {
    verify_with(&StandardPolicy::new(), keyrings, data, signatures)
}

fn verify_with(policy: &dyn Policy, keyrings: &[&[u8]], data: &[u8], signatures: &[u8]) -> Result<Vec<SigInfo>> {
    let mut certs = Vec::new();
    for keyring in keyrings {
        certs.extend(parse_certs(keyring));
    }
    let helper = Helper { policy, certs, now: SystemTime::now(), signatures: Vec::new() };
    let mut verifier = DetachedVerifierBuilder::from_bytes(signatures)
        .context("Unable to read signature")?
        .with_policy(policy, None, helper)
        .context("Unable to read signature")?;
    verifier.verify_bytes(data).context("Unable to complete signature verification")?;
    Ok(verifier.into_helper().signatures)
}

/// A message that carries its signatures: the signatures, and the content
/// if one of them is valid.
fn verify_message(keyrings: &[&[u8]], message: &[u8]) -> Result<(Vec<SigInfo>, Option<Vec<u8>>)> {
    verify_message_with(&StandardPolicy::new(), keyrings, message)
}

fn verify_message_with(
    policy: &dyn Policy,
    keyrings: &[&[u8]],
    message: &[u8],
) -> Result<(Vec<SigInfo>, Option<Vec<u8>>)> {
    let mut certs = Vec::new();
    for keyring in keyrings {
        certs.extend(parse_certs(keyring));
    }
    let helper = Helper { policy, certs, now: SystemTime::now(), signatures: Vec::new() };
    let mut verifier = VerifierBuilder::from_bytes(message)
        .context("Unable to read signed data")?
        .with_policy(policy, None, helper)
        .context("Unable to read signed data")?;
    let mut content = Vec::new();
    std::io::copy(&mut verifier, &mut content).context("Unable to complete signature verification")?;
    let signatures = verifier.into_helper().signatures;
    // Unverified content must not reach a caller that forgets to look.
    let content = if signatures.iter().any(|s| s.valid) { Some(content) } else { None };
    Ok((signatures, content))
}

/// Whether ID, a key ID or fingerprint as gpg takes them, names a key of CERT.
fn names_key(cert: &Cert, id: &str) -> bool {
    let id = id.trim().trim_start_matches("0x").trim_start_matches("0X").replace(' ', "").to_uppercase();
    if id.len() < 8 || !id.bytes().all(|b| b.is_ascii_hexdigit()) {
        return false;
    }
    cert.keys().any(|k| hex(&k.key().fingerprint()).ends_with(&id))
}

fn keyring_import(keyring: &[u8], source: &[u8], key_ids: Option<&[String]>) -> Result<(Vec<u8>, u32)> {
    let mut ring = parse_certs(keyring);
    let source: Vec<Cert> = CertParser::from_bytes(source)
        .context("Unable to import keys")?
        .collect::<openpgp::Result<Vec<_>>>()
        .context("Unable to import keys")?;

    let selected: Vec<Cert> = match key_ids {
        None => source,
        Some(ids) => {
            let mut selected: Vec<Cert> = Vec::new();
            for id in ids {
                let mut found = false;
                for cert in source.iter().filter(|c| names_key(c, id)) {
                    found = true;
                    if !selected.iter().any(|c| c.fingerprint() == cert.fingerprint()) {
                        selected.push(cert.clone());
                    }
                }
                if !found {
                    return Err(anyhow!("Unable to find key \"{}\"", id));
                }
            }
            selected
        }
    };

    let mut imported = 0;
    for cert in selected {
        let cert = cert.strip_secret_key_material();
        match ring.iter().position(|c| c.fingerprint() == cert.fingerprint()) {
            Some(i) => {
                let fpr = hex(&cert.fingerprint());
                let old = ring.remove(i);
                let merged = old
                    .merge_public(cert)
                    .with_context(|| format!("Unable to import key \"{}\"", fpr))?;
                ring.insert(i, merged);
            }
            None => {
                ring.push(cert);
                imported += 1;
            }
        }
    }

    let mut out = Vec::new();
    for cert in &ring {
        cert.serialize(&mut out).context("Unable to write keyring")?;
    }
    Ok((out, imported))
}

// The C interface.

unsafe fn slice<'a>(data: *const u8, len: usize) -> &'a [u8] {
    if data.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(data, len)
    }
}

fn c_string(s: &str) -> *mut c_char {
    // A NUL inside would truncate; user IDs are free-form bytes.
    CString::new(s.replace('\0', "")).map(CString::into_raw).unwrap_or(ptr::null_mut())
}

unsafe fn set_error(error: *mut *mut c_char, message: &str) {
    if !error.is_null() {
        *error = c_string(message);
    }
}

unsafe fn run<F: FnOnce() -> Result<()>>(error: *mut *mut c_char, f: F) -> c_int {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            set_error(error, &format!("{:#}", e));
            -1
        }
        Err(_) => {
            set_error(error, "internal error in the OpenPGP implementation");
            -1
        }
    }
}

unsafe fn keyring_slices<'a>(keyrings: *const OpvBuffer, n_keyrings: usize) -> Vec<&'a [u8]> {
    if keyrings.is_null() {
        Vec::new()
    } else {
        std::slice::from_raw_parts(keyrings, n_keyrings).iter().map(|b| slice(b.data, b.len)).collect()
    }
}

unsafe fn give_signatures(infos: &[SigInfo], out_signatures: *mut *mut OpvSignature, out_n_signatures: *mut usize) {
    let sigs: Vec<OpvSignature> = infos
        .iter()
        .map(|i| OpvSignature {
            valid: i.valid as u8,
            sig_expired: i.sig_expired as u8,
            key_expired: i.key_expired as u8,
            key_revoked: i.key_revoked as u8,
            key_missing: i.key_missing as u8,
            timestamp: i.timestamp,
            exp_timestamp: i.exp_timestamp,
            key_exp_timestamp: i.key_exp_timestamp,
            key_exp_timestamp_primary: i.key_exp_timestamp_primary,
            fingerprint: c_string(&i.fingerprint),
            fingerprint_primary: c_string(&i.fingerprint_primary),
            pubkey_algo_name: c_string(&i.pubkey_algo_name),
            hash_algo_name: c_string(&i.hash_algo_name),
            user_name: i.user_name.as_deref().map_or(ptr::null_mut(), c_string),
            user_email: i.user_email.as_deref().map_or(ptr::null_mut(), c_string),
            cert_fingerprints: c_string(&i.cert_fingerprints),
        })
        .collect();
    let boxed = sigs.into_boxed_slice();
    *out_n_signatures = boxed.len();
    *out_signatures = Box::into_raw(boxed) as *mut OpvSignature;
}

/// # Safety
/// See openpgp-verify-sequoia.h.
#[no_mangle]
pub unsafe extern "C" fn opv_verify(
    keyrings: *const OpvBuffer,
    n_keyrings: usize,
    data: *const u8,
    data_len: usize,
    signatures: *const u8,
    signatures_len: usize,
    out_signatures: *mut *mut OpvSignature,
    out_n_signatures: *mut usize,
    error: *mut *mut c_char,
) -> c_int {
    run(error, || {
        if out_signatures.is_null() || out_n_signatures.is_null() {
            return Err(anyhow!("invalid argument"));
        }
        let keyrings = keyring_slices(keyrings, n_keyrings);
        let infos = verify(&keyrings, slice(data, data_len), slice(signatures, signatures_len))?;
        give_signatures(&infos, out_signatures, out_n_signatures);
        Ok(())
    })
}

/// # Safety
/// See openpgp-verify-sequoia.h.
#[no_mangle]
pub unsafe extern "C" fn opv_verify_message(
    keyrings: *const OpvBuffer,
    n_keyrings: usize,
    message: *const u8,
    message_len: usize,
    out_signatures: *mut *mut OpvSignature,
    out_n_signatures: *mut usize,
    out_content: *mut *mut u8,
    out_content_len: *mut usize,
    error: *mut *mut c_char,
) -> c_int {
    run(error, || {
        if out_signatures.is_null() || out_n_signatures.is_null() || out_content.is_null() || out_content_len.is_null() {
            return Err(anyhow!("invalid argument"));
        }
        let keyrings = keyring_slices(keyrings, n_keyrings);
        let (infos, content) = verify_message(&keyrings, slice(message, message_len))?;
        give_signatures(&infos, out_signatures, out_n_signatures);
        match content {
            Some(content) => {
                let boxed = content.into_boxed_slice();
                *out_content_len = boxed.len();
                *out_content = Box::into_raw(boxed) as *mut u8;
            }
            None => {
                *out_content_len = 0;
                *out_content = ptr::null_mut();
            }
        }
        Ok(())
    })
}

/// # Safety
/// SIGNATURES and N_SIGNATURES must come from opv_verify().
#[no_mangle]
pub unsafe extern "C" fn opv_signatures_free(signatures: *mut OpvSignature, n_signatures: usize) {
    if signatures.is_null() {
        return;
    }
    let boxed = Box::from_raw(ptr::slice_from_raw_parts_mut(signatures, n_signatures));
    for sig in boxed.iter() {
        for s in [
            sig.fingerprint,
            sig.fingerprint_primary,
            sig.pubkey_algo_name,
            sig.hash_algo_name,
            sig.user_name,
            sig.user_email,
            sig.cert_fingerprints,
        ] {
            opv_string_free(s);
        }
    }
}

/// # Safety
/// See openpgp-verify-sequoia.h.
#[no_mangle]
pub unsafe extern "C" fn opv_keyring_import(
    keyring: *const u8,
    keyring_len: usize,
    source: *const u8,
    source_len: usize,
    key_ids: *const *const c_char,
    out_keyring: *mut *mut u8,
    out_keyring_len: *mut usize,
    out_imported: *mut c_uint,
    error: *mut *mut c_char,
) -> c_int {
    run(error, || {
        if out_keyring.is_null() || out_keyring_len.is_null() {
            return Err(anyhow!("invalid argument"));
        }
        let ids = if key_ids.is_null() {
            None
        } else {
            let mut ids = Vec::new();
            let mut p = key_ids;
            while !(*p).is_null() {
                ids.push(CStr::from_ptr(*p).to_string_lossy().into_owned());
                p = p.add(1);
            }
            Some(ids)
        };
        let (ring, imported) = keyring_import(slice(keyring, keyring_len), slice(source, source_len), ids.as_deref())?;
        let boxed = ring.into_boxed_slice();
        *out_keyring_len = boxed.len();
        *out_keyring = Box::into_raw(boxed) as *mut u8;
        if !out_imported.is_null() {
            *out_imported = imported;
        }
        Ok(())
    })
}

/// # Safety
/// BYTES and LEN must come from this library.
#[no_mangle]
pub unsafe extern "C" fn opv_bytes_free(bytes: *mut u8, len: usize) {
    if !bytes.is_null() {
        drop(Box::from_raw(ptr::slice_from_raw_parts_mut(bytes, len)));
    }
}

/// # Safety
/// STRING must come from this library.
#[no_mangle]
pub unsafe extern "C" fn opv_string_free(string: *mut c_char) {
    if !string.is_null() {
        drop(CString::from_raw(string));
    }
}

#[cfg(test)]
mod tests;
