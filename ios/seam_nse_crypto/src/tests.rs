//! Round trips through the C ABI with pickles built the way the Dart SDK
//! builds them.
//!
//! The vodozemac pickle mirrors `KeyManager.setInboundGroupSession` in the
//! matrix Dart SDK: `vod.InboundGroupSession(session_key)` with session config
//! version 1, then `toPickleEncrypted(userId.toPickleKey())`. The libolm
//! pickle is assembled byte by byte in libolm's inbound group session layout
//! and encrypted with vodozemac's libolm pickle cipher, keyed by the UTF-8
//! bytes of the user id as `SessionKey.fromDb` passes it.

use std::ffi::{c_char, CStr, CString};
use std::ptr;

use vodozemac::hazmat::Cipher;
use vodozemac::megolm::{GroupSession, InboundGroupSession, SessionConfig};

use super::*;

const USER_ID: &str = "@alice:example.org";
const PAYLOAD: &str = r#"{"type":"m.room.message","content":{"msgtype":"m.text","body":"hello from alice"},"room_id":"!room:example.org"}"#;

struct Fixture {
    inbound: InboundGroupSession,
    ciphertext: String,
}

/// An outbound session that has encrypted one message, and the inbound
/// session a recipient builds from its session key.
fn fixture() -> Fixture {
    let mut outbound = GroupSession::new(SessionConfig::version_1());
    let inbound = InboundGroupSession::new(&outbound.session_key(), SessionConfig::version_1());
    let ciphertext = outbound.encrypt(PAYLOAD).to_base64();
    Fixture { inbound, ciphertext }
}

fn dart_pickle(inbound: &InboundGroupSession, user_id: &str) -> String {
    inbound.pickle().encrypt(&pickle_key_for_user_id(user_id))
}

/// A libolm `OLM_INBOUND_GROUP_SESSION` pickle, version 2: the initial and
/// latest ratchets (128 bytes and a big-endian u32 index each), the Ed25519
/// signing key and the signing-key-verified flag.
fn libolm_pickle(inbound: &InboundGroupSession, key: &[u8]) -> String {
    // ExportedSessionKey bytes: version (1), index (4), ratchet (128), key (32).
    let exported = inbound.export_at_first_known_index().to_bytes();
    let index = &exported[1..5];
    let ratchet = &exported[5..133];
    let signing_key = &exported[133..165];

    let mut plain = Vec::new();
    plain.extend_from_slice(&2u32.to_be_bytes());
    for _ in 0..2 {
        plain.extend_from_slice(ratchet);
        plain.extend_from_slice(index);
    }
    plain.extend_from_slice(signing_key);
    plain.push(1);

    vodozemac::base64_encode(Cipher::new_pickle(key).encrypt_pickle(&plain))
}

fn cstr(s: &str) -> CString {
    CString::new(s).unwrap()
}

/// Calls `seam_megolm_decrypt` and returns the code and, on success, the
/// plaintext and message index.
fn call_decrypt(pickle: &str, key: &[u8], ciphertext: &str) -> (i32, Option<(String, u32)>) {
    let pickle = cstr(pickle);
    let ciphertext = cstr(ciphertext);
    let mut out: *mut c_char = ptr::null_mut();
    let mut index = u32::MAX;
    let code = unsafe {
        seam_megolm_decrypt(
            pickle.as_ptr(),
            key.as_ptr(),
            key.len(),
            ciphertext.as_ptr(),
            &mut out,
            &mut index,
        )
    };
    (code, take(code, out, index))
}

fn call_decrypt_for_user(pickle: &str, user_id: &str, ciphertext: &str) -> (i32, Option<(String, u32)>) {
    let pickle = cstr(pickle);
    let user_id = cstr(user_id);
    let ciphertext = cstr(ciphertext);
    let mut out: *mut c_char = ptr::null_mut();
    let mut index = u32::MAX;
    let code = unsafe {
        seam_megolm_decrypt_for_user(pickle.as_ptr(), user_id.as_ptr(), ciphertext.as_ptr(), &mut out, &mut index)
    };
    (code, take(code, out, index))
}

fn take(code: i32, out: *mut c_char, index: u32) -> Option<(String, u32)> {
    if code != SEAM_OK {
        assert!(out.is_null(), "out_plaintext must stay untouched on failure");
        assert_eq!(index, u32::MAX, "out_message_index must stay untouched on failure");
        return None;
    }
    let text = unsafe { CStr::from_ptr(out) }.to_str().unwrap().to_owned();
    unsafe { seam_string_free(out) };
    Some((text, index))
}

#[test]
fn pickle_key_matches_dart_to_pickle_key() {
    let key = pickle_key_for_user_id(USER_ID);
    let mut expected = [0u8; 32];
    expected[..USER_ID.len()].copy_from_slice(USER_ID.as_bytes());
    assert_eq!(*key, expected);

    // Longer than 32 code units: truncated.
    let long = "@a-very-long-localpart-indeed:example.org";
    assert_eq!(&key_bytes(long)[..], &long.as_bytes()[..32]);

    // Non-ASCII: one byte per UTF-16 code unit, low 8 bits kept, as
    // Uint8List.fromList(codeUnits) does. U+00E9 is 0xE9, U+0100 is 0x00,
    // and U+1F600 is the surrogate pair D83D DE00, giving 0x3D 0x00.
    let k = key_bytes("@\u{e9}\u{100}\u{1F600}");
    assert_eq!(&k[..5], &[b'@', 0xE9, 0x00, 0x3D, 0x00]);
    assert!(k[5..].iter().all(|b| *b == 0));
}

fn key_bytes(user_id: &str) -> [u8; 32] {
    *pickle_key_for_user_id(user_id)
}

#[test]
fn decrypts_dart_pickle_with_explicit_key() {
    let f = fixture();
    let pickle = dart_pickle(&f.inbound, USER_ID);
    let (code, result) = call_decrypt(&pickle, &key_bytes(USER_ID), &f.ciphertext);
    assert_eq!(code, SEAM_OK);
    assert_eq!(result, Some((PAYLOAD.to_owned(), 0)));
}

#[test]
fn decrypts_dart_pickle_for_user() {
    let f = fixture();
    let pickle = dart_pickle(&f.inbound, USER_ID);
    let (code, result) = call_decrypt_for_user(&pickle, USER_ID, &f.ciphertext);
    assert_eq!(code, SEAM_OK);
    assert_eq!(result, Some((PAYLOAD.to_owned(), 0)));
}

#[test]
fn reports_message_index_of_later_messages() {
    let mut outbound = GroupSession::new(SessionConfig::version_1());
    let inbound = InboundGroupSession::new(&outbound.session_key(), SessionConfig::version_1());
    let _first = outbound.encrypt("first");
    let second = outbound.encrypt(PAYLOAD).to_base64();
    let pickle = dart_pickle(&inbound, USER_ID);
    let (code, result) = call_decrypt_for_user(&pickle, USER_ID, &second);
    assert_eq!(code, SEAM_OK);
    assert_eq!(result, Some((PAYLOAD.to_owned(), 1)));
}

#[test]
fn decrypts_legacy_libolm_pickle_for_user() {
    let f = fixture();
    let pickle = libolm_pickle(&f.inbound, USER_ID.as_bytes());
    let (code, result) = call_decrypt_for_user(&pickle, USER_ID, &f.ciphertext);
    assert_eq!(code, SEAM_OK);
    assert_eq!(result, Some((PAYLOAD.to_owned(), 0)));
}

#[test]
fn explicit_key_entry_point_rejects_libolm_pickle() {
    let f = fixture();
    let pickle = libolm_pickle(&f.inbound, USER_ID.as_bytes());
    let (code, _) = call_decrypt(&pickle, &key_bytes(USER_ID), &f.ciphertext);
    assert_eq!(code, SEAM_ERR_BAD_PICKLE);
}

#[test]
fn wrong_user_rejects_pickle() {
    let f = fixture();
    let pickle = dart_pickle(&f.inbound, USER_ID);
    let (code, _) = call_decrypt_for_user(&pickle, "@mallory:example.org", &f.ciphertext);
    assert_eq!(code, SEAM_ERR_BAD_PICKLE);

    let libolm = libolm_pickle(&f.inbound, USER_ID.as_bytes());
    let (code, _) = call_decrypt_for_user(&libolm, "@mallory:example.org", &f.ciphertext);
    assert_eq!(code, SEAM_ERR_BAD_PICKLE);
}

#[test]
fn wrong_key_rejects_pickle() {
    let f = fixture();
    let pickle = dart_pickle(&f.inbound, USER_ID);
    let mut key = key_bytes(USER_ID);
    key[0] ^= 1;
    let (code, _) = call_decrypt(&pickle, &key, &f.ciphertext);
    assert_eq!(code, SEAM_ERR_BAD_PICKLE);
}

#[test]
fn bad_key_length_is_reported() {
    let f = fixture();
    let pickle = dart_pickle(&f.inbound, USER_ID);
    let (code, _) = call_decrypt(&pickle, &key_bytes(USER_ID)[..31], &f.ciphertext);
    assert_eq!(code, SEAM_ERR_BAD_KEY_LENGTH);
    let (code, _) = call_decrypt(&pickle, USER_ID.as_bytes(), &f.ciphertext);
    assert_eq!(code, SEAM_ERR_BAD_KEY_LENGTH);
}

#[test]
fn truncated_pickle_is_reported() {
    let f = fixture();
    let pickle = dart_pickle(&f.inbound, USER_ID);
    let truncated = &pickle[..pickle.len() / 2];
    let (code, _) = call_decrypt(truncated, &key_bytes(USER_ID), &f.ciphertext);
    assert_eq!(code, SEAM_ERR_BAD_PICKLE);
    let (code, _) = call_decrypt_for_user(truncated, USER_ID, &f.ciphertext);
    assert_eq!(code, SEAM_ERR_BAD_PICKLE);
}

#[test]
fn garbage_ciphertext_is_reported() {
    let f = fixture();
    let pickle = dart_pickle(&f.inbound, USER_ID);
    for garbage in ["", "not base64 at all!", "AAAA"] {
        let (code, _) = call_decrypt_for_user(&pickle, USER_ID, garbage);
        assert_eq!(code, SEAM_ERR_BAD_CIPHERTEXT, "input {garbage:?}");
    }
}

#[test]
fn message_from_another_session_fails_to_decrypt() {
    let f = fixture();
    let pickle = dart_pickle(&f.inbound, USER_ID);
    let other = fixture();
    let (code, _) = call_decrypt_for_user(&pickle, USER_ID, &other.ciphertext);
    assert_eq!(code, SEAM_ERR_DECRYPT);
}

#[test]
fn tampered_ciphertext_fails_to_decrypt() {
    let f = fixture();
    let pickle = dart_pickle(&f.inbound, USER_ID);
    let mut bytes = vodozemac::base64_decode(&f.ciphertext).unwrap();
    // Flip a bit inside the AES ciphertext, past the version and index.
    bytes[10] ^= 1;
    let tampered = vodozemac::base64_encode(bytes);
    let (code, _) = call_decrypt_for_user(&pickle, USER_ID, &tampered);
    assert_eq!(code, SEAM_ERR_DECRYPT);
}

#[test]
fn non_utf8_plaintext_is_reported() {
    let mut outbound = GroupSession::new(SessionConfig::version_1());
    let inbound = InboundGroupSession::new(&outbound.session_key(), SessionConfig::version_1());
    let ciphertext = outbound.encrypt([0xFFu8, 0xFE, 0x00]).to_base64();
    let pickle = dart_pickle(&inbound, USER_ID);
    let (code, _) = call_decrypt_for_user(&pickle, USER_ID, &ciphertext);
    assert_eq!(code, SEAM_ERR_PLAINTEXT_NOT_UTF8);
}

#[test]
fn non_utf8_input_is_reported() {
    let f = fixture();
    let pickle = cstr(&dart_pickle(&f.inbound, USER_ID));
    let bad_user = CString::new(vec![b'@', 0xFF, b'x']).unwrap();
    let ciphertext = cstr(&f.ciphertext);
    let mut out: *mut c_char = ptr::null_mut();
    let mut index = 0u32;
    let code = unsafe {
        seam_megolm_decrypt_for_user(pickle.as_ptr(), bad_user.as_ptr(), ciphertext.as_ptr(), &mut out, &mut index)
    };
    assert_eq!(code, SEAM_ERR_INPUT_NOT_UTF8);
    assert!(out.is_null());
}

#[test]
fn null_arguments_are_reported() {
    let key = key_bytes(USER_ID);
    let mut out: *mut c_char = ptr::null_mut();
    let mut index = 0u32;
    let s = cstr("x");
    let code = unsafe { seam_megolm_decrypt(ptr::null(), key.as_ptr(), 32, s.as_ptr(), &mut out, &mut index) };
    assert_eq!(code, SEAM_ERR_NULL_ARGUMENT);
    let code = unsafe { seam_megolm_decrypt(s.as_ptr(), ptr::null(), 32, s.as_ptr(), &mut out, &mut index) };
    assert_eq!(code, SEAM_ERR_NULL_ARGUMENT);
    let code = unsafe { seam_megolm_decrypt_for_user(s.as_ptr(), s.as_ptr(), s.as_ptr(), ptr::null_mut(), &mut index) };
    assert_eq!(code, SEAM_ERR_NULL_ARGUMENT);
    unsafe { seam_string_free(ptr::null_mut()) };
}

#[test]
fn panics_are_caught() {
    assert_eq!(guarded(|| panic!("boom")), SEAM_ERR_PANIC);
}
