// SPDX-License-Identifier: LGPL-2.0-or-later
//
// Run against libostree's own vectors:
//   OSTREE_GPG_VERIFY_DATA=<ostree>/tests/gpg-verify-data cargo test
// Without the variable the tests pass without checking anything.
//
// The expected values are those of libostree's test-gpg-verify-result.c,
// which checks the same files through GPGME.

use super::*;
use std::path::PathBuf;

fn data_dir() -> Option<PathBuf> {
    std::env::var_os("OSTREE_GPG_VERIFY_DATA").map(PathBuf::from)
}

/// The vectors are from 2015 and signed with SHA1, which gpg still takes
/// for data signatures and Sequoia's standard policy does not.
fn sha1_policy() -> StandardPolicy<'static> {
    let mut policy = StandardPolicy::new();
    policy.accept_hash(HashAlgorithm::SHA1);
    policy
}

fn check_with(policy: &dyn Policy, sig: &str) -> Option<Vec<SigInfo>> {
    let dir = data_dir()?;
    let keyring = std::fs::read(dir.join("pubring.gpg")).unwrap();
    let data = std::fs::read(dir.join("lgpl2")).unwrap();
    let sig = std::fs::read(dir.join(sig)).unwrap();
    Some(verify_with(policy, &[&keyring], &data, &sig).unwrap())
}

fn check(sig: &str) -> Option<Vec<SigInfo>> {
    check_with(&sha1_policy(), sig)
}

/// (valid, sig_expired, key_expired, key_revoked, key_missing, key_exp_timestamp)
fn flags(i: &SigInfo) -> (bool, bool, bool, bool, bool, i64) {
    (i.valid, i.sig_expired, i.key_expired, i.key_revoked, i.key_missing, i.key_exp_timestamp)
}

#[test]
fn valid_signature() {
    let Some(sigs) = check("lgpl2.sig0") else { return };
    assert_eq!(sigs.len(), 1);
    assert_eq!(flags(&sigs[0]), (true, false, false, false, false, 0));
    assert_eq!(sigs[0].pubkey_algo_name, "RSA");
    assert_eq!(sigs[0].hash_algo_name, "SHA1");
    assert_eq!(sigs[0].user_name.as_deref(), Some("J. Random User"));
    assert_eq!(sigs[0].user_email.as_deref(), Some("testcase@redhat.com"));
    assert_eq!(sigs[0].fingerprint, sigs[0].fingerprint_primary);
}

#[test]
fn expired_key() {
    let Some(sigs) = check("lgpl2.sig1") else { return };
    assert_eq!(flags(&sigs[0]), (false, false, true, false, false, 1426782201));
}

#[test]
fn revoked_key() {
    let Some(sigs) = check("lgpl2.sig2") else { return };
    assert_eq!(flags(&sigs[0]), (false, false, false, true, false, 0));
}

#[test]
fn missing_key() {
    let Some(sigs) = check("lgpl2.sig3") else { return };
    assert_eq!(flags(&sigs[0]), (false, false, false, false, true, 0));
    assert_eq!(sigs[0].fingerprint_primary, "");
    assert_eq!(sigs[0].user_name, None);
}

#[test]
fn expired_signature() {
    let Some(sigs) = check("lgpl2.sig4") else { return };
    assert_eq!(flags(&sigs[0]), (false, true, false, false, false, 0));
}

#[test]
fn all_signatures() {
    let Some(sigs) = check("lgpl2.sig") else { return };
    assert_eq!(sigs.len(), 5);
    assert_eq!(sigs.iter().filter(|i| i.valid).count(), 1);
}

#[test]
fn tampered_data() {
    let Some(dir) = data_dir() else { return };
    let keyring = std::fs::read(dir.join("pubring.gpg")).unwrap();
    let mut data = std::fs::read(dir.join("lgpl2")).unwrap();
    data[0] ^= 1;
    let sig = std::fs::read(dir.join("lgpl2.sig0")).unwrap();
    let sigs = verify_with(&sha1_policy(), &[&keyring], &data, &sig).unwrap();
    assert_eq!(sigs.len(), 1);
    assert!(!sigs[0].valid);
    assert!(!sigs[0].key_missing);
}

#[test]
fn standard_policy_rejects_sha1() {
    let Some(sigs) = check_with(&StandardPolicy::new(), "lgpl2.sig0") else { return };
    assert!(!sigs[0].valid);
}

#[test]
fn import_into_empty_keyring() {
    let Some(dir) = data_dir() else { return };
    let source = std::fs::read(dir.join("pubring.gpg")).unwrap();
    let (ring, imported) = keyring_import(&[], &source, None).unwrap();
    let certs = parse_certs(&ring);
    assert_eq!(imported as usize, certs.len());
    assert!(imported >= 3);
    // Importing the same keys again adds none and loses none.
    let (again, imported) = keyring_import(&ring, &source, None).unwrap();
    assert_eq!(imported, 0);
    assert_eq!(parse_certs(&again).len(), certs.len());
}

#[test]
fn import_selected_key() {
    let Some(dir) = data_dir() else { return };
    let source = std::fs::read(dir.join("pubring.gpg")).unwrap();
    // By long key ID, as "ostree remote gpg-import -k" takes it.
    let ids = vec!["E8B35B6C9A51B00B".to_string()];
    let (ring, imported) = keyring_import(&[], &source, Some(&ids)).unwrap();
    assert_eq!(imported, 1);
    assert_eq!(hex(&parse_certs(&ring)[0].fingerprint()), "F1F38B2F90F0612E8258D5B2E8B35B6C9A51B00B");
    let ids = vec!["0123456789ABCDEF".to_string()];
    assert!(keyring_import(&[], &source, Some(&ids)).is_err());
}

/// A real remote: FLATHUB_DATA holds flathub.gpg, summary.idx and
/// summary.idx.sig. Checked with the policy libostree gets.
#[test]
fn flathub_summary_index() {
    let Some(dir) = std::env::var_os("FLATHUB_DATA").map(PathBuf::from) else { return };
    let keyring = std::fs::read(dir.join("flathub.gpg")).unwrap();
    let data = std::fs::read(dir.join("summary.idx")).unwrap();
    let sig = std::fs::read(dir.join("summary.idx.sig")).unwrap();
    let sigs = verify(&[&keyring], &data, &sig).unwrap();
    for i in &sigs {
        eprintln!(
            "flathub: valid={} fpr={} primary={} {}/{} ts={} keyexp={}/{} {:?} <{:?}>",
            i.valid, i.fingerprint, i.fingerprint_primary, i.pubkey_algo_name, i.hash_algo_name,
            i.timestamp, i.key_exp_timestamp, i.key_exp_timestamp_primary, i.user_name, i.user_email
        );
    }
    assert!(sigs.iter().any(|i| i.valid));
    let mut bad = data.clone();
    bad[10] ^= 1;
    assert!(!verify(&[&keyring], &bad, &sig).unwrap().iter().any(|i| i.valid));
}

/// A message that carries its signature, as the signatures of OCI remotes
/// do. Made here: (certificate, signed message).
fn signed_message(content: &[u8]) -> (Vec<u8>, Vec<u8>) {
    use openpgp::serialize::stream::{LiteralWriter, Message, Signer};
    use std::io::Write;

    let (cert, _) = CertBuilder::new().add_userid("Test <test@example.invalid>").add_signing_subkey().generate().unwrap();
    let policy = StandardPolicy::new();
    let keypair = cert
        .keys()
        .unencrypted_secret()
        .with_policy(&policy, None)
        .for_signing()
        .next()
        .unwrap()
        .key()
        .clone()
        .into_keypair()
        .unwrap();
    let mut message = Vec::new();
    {
        let sink = Message::new(&mut message);
        let signer = Signer::new(sink, keypair).unwrap().build().unwrap();
        let mut literal = LiteralWriter::new(signer).build().unwrap();
        literal.write_all(content).unwrap();
        literal.finalize().unwrap();
    }
    let mut public = Vec::new();
    cert.strip_secret_key_material().serialize(&mut public).unwrap();
    (public, message)
}

#[test]
fn message_with_valid_signature() {
    let (cert, message) = signed_message(b"{\"critical\": {}}");
    let (sigs, content) = verify_message(&[&cert], &message).unwrap();
    assert_eq!(sigs.len(), 1);
    assert!(sigs[0].valid);
    assert_ne!(sigs[0].fingerprint, sigs[0].fingerprint_primary);
    assert_eq!(content.as_deref(), Some(&b"{\"critical\": {}}"[..]));
}

#[test]
fn message_from_unknown_key_gives_no_content() {
    let (_, message) = signed_message(b"content");
    let (other, _) = signed_message(b"other");
    let (sigs, content) = verify_message(&[&other], &message).unwrap();
    assert_eq!(sigs.len(), 1);
    assert!(!sigs[0].valid);
    assert!(sigs[0].key_missing);
    assert_eq!(content, None);
    // And with no keyring at all.
    let (sigs, content) = verify_message(&[], &message).unwrap();
    assert!(sigs[0].key_missing);
    assert_eq!(content, None);
}

#[test]
fn tampered_message_gives_no_content() {
    let (cert, mut message) = signed_message(b"content that is long enough to find");
    let at = message.windows(7).position(|w| w == b"content").unwrap();
    message[at] ^= 1;
    match verify_message(&[&cert], &message) {
        Ok((sigs, content)) => {
            assert!(!sigs.iter().any(|s| s.valid));
            assert_eq!(content, None);
        }
        // Refusing the message outright is as good.
        Err(_) => {}
    }
}

#[test]
fn unsigned_message_gives_no_content() {
    use openpgp::serialize::stream::{LiteralWriter, Message};
    use std::io::Write;

    let mut message = Vec::new();
    {
        let sink = Message::new(&mut message);
        let mut literal = LiteralWriter::new(sink).build().unwrap();
        literal.write_all(b"content").unwrap();
        literal.finalize().unwrap();
    }
    let (cert, _) = signed_message(b"other");
    match verify_message(&[&cert], &message) {
        Ok((sigs, content)) => {
            assert!(sigs.is_empty());
            assert_eq!(content, None);
        }
        Err(_) => {}
    }
}

/// A message made by gpg itself: GPG_MESSAGE_DATA holds key.gpg,
/// message.gpg (gpg --sign, compressed as gpg does) and content.json.
#[test]
fn message_made_by_gpg() {
    let Some(dir) = std::env::var_os("GPG_MESSAGE_DATA").map(PathBuf::from) else { return };
    let key = std::fs::read(dir.join("key.gpg")).unwrap();
    let message = std::fs::read(dir.join("message.gpg")).unwrap();
    let expected = std::fs::read(dir.join("content.json")).unwrap();
    let (sigs, content) = verify_message(&[&key], &message).unwrap();
    assert_eq!(sigs.len(), 1);
    assert!(sigs[0].valid);
    assert_eq!(content, Some(expected));
}
