//! Megolm decryption for Seam's iOS Notification Service Extension.
//!
//! The extension runs without the Flutter engine, so it cannot use the Dart
//! Matrix SDK to decrypt the event a push points at. This crate reads the
//! inbound group session pickles the Dart SDK stores and decrypts one
//! `m.megolm.v1.aes-sha2` ciphertext, behind a small C ABI that Swift calls.
//!
//! It links the same vodozemac release as `flutter_vodozemac` 0.9.0, so the
//! pickle format is read by the code that wrote it. Nothing here writes a
//! pickle back: decrypting only reads the stored ratchet, and the extension
//! keeps the database read-only.
//!
//! Every entry point catches panics, so an unwind never crosses into Swift.
//! Key material and plaintext are never logged.

#![deny(unsafe_op_in_unsafe_fn)]

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

use vodozemac::megolm::{InboundGroupSession, InboundGroupSessionPickle, MegolmMessage};
use zeroize::Zeroizing;

/// Decryption succeeded and the out parameters are set.
pub const SEAM_OK: i32 = 0;
/// A required pointer argument was null.
pub const SEAM_ERR_NULL_ARGUMENT: i32 = -1;
/// The pickle key is not exactly 32 bytes long.
pub const SEAM_ERR_BAD_KEY_LENGTH: i32 = -2;
/// The pickle could not be read in any accepted format with the given key.
pub const SEAM_ERR_BAD_PICKLE: i32 = -3;
/// The ciphertext is not a base64 encoded Megolm message.
pub const SEAM_ERR_BAD_CIPHERTEXT: i32 = -4;
/// The message did not decrypt: bad signature or MAC, or a message index
/// before the session's first known index.
pub const SEAM_ERR_DECRYPT: i32 = -5;
/// The decrypted plaintext is not valid UTF-8.
pub const SEAM_ERR_PLAINTEXT_NOT_UTF8: i32 = -6;
/// A string argument (pickle, ciphertext or user id) is not valid UTF-8.
pub const SEAM_ERR_INPUT_NOT_UTF8: i32 = -7;
/// The plaintext contains a NUL byte and cannot be returned as a C string.
pub const SEAM_ERR_PLAINTEXT_HAS_NUL: i32 = -8;
/// A panic was caught inside the library.
pub const SEAM_ERR_PANIC: i32 = -99;

/// Derives the 32-byte pickle key the Dart SDK uses for a user id.
///
/// This mirrors `PickleKeyStringExtension.toPickleKey` in the matrix Dart SDK
/// (`lib/encryption/utils/pickle_key.dart`): it takes the string's UTF-16 code
/// units, keeps the low 8 bits of each (that is what `Uint8List.fromList`
/// does with values above 255), then pads with zero bytes or truncates to 32.
/// For an ASCII user id that is simply its bytes, zero padded.
pub fn pickle_key_for_user_id(user_id: &str) -> Zeroizing<[u8; 32]> {
    let mut key = Zeroizing::new([0u8; 32]);
    for (slot, unit) in key.iter_mut().zip(user_id.encode_utf16()) {
        *slot = unit as u8;
    }
    key
}

/// Restores an inbound group session from a vodozemac encrypted pickle.
fn unpickle_vodozemac(pickle: &str, key: &[u8; 32]) -> Option<InboundGroupSession> {
    InboundGroupSessionPickle::from_encrypted(pickle, key)
        .ok()
        .map(InboundGroupSession::from)
}

/// Restores an inbound group session the way `SessionKey.fromDb` does in the
/// Dart SDK (`lib/encryption/utils/session_key.dart`): first the vodozemac
/// pickle with `userId.toPickleKey()`, then the legacy libolm pickle with the
/// UTF-8 bytes of the full user id as its key.
fn unpickle_for_user(pickle: &str, user_id: &str) -> Option<InboundGroupSession> {
    let key = pickle_key_for_user_id(user_id);
    unpickle_vodozemac(pickle, &key)
        .or_else(|| InboundGroupSession::from_libolm_pickle(pickle, user_id.as_bytes()).ok())
}

/// The outcome of a decryption, before it is handed across the C boundary.
struct Decrypted {
    plaintext: CString,
    message_index: u32,
}

fn decrypt_with(session: &mut InboundGroupSession, ciphertext: &str) -> Result<Decrypted, i32> {
    let message = MegolmMessage::from_base64(ciphertext).map_err(|_| SEAM_ERR_BAD_CIPHERTEXT)?;
    let decrypted = session.decrypt(&message).map_err(|_| SEAM_ERR_DECRYPT)?;
    let message_index = decrypted.message_index;
    let plaintext = String::from_utf8(decrypted.plaintext).map_err(|_| SEAM_ERR_PLAINTEXT_NOT_UTF8)?;
    let plaintext = CString::new(plaintext).map_err(|_| SEAM_ERR_PLAINTEXT_HAS_NUL)?;
    Ok(Decrypted { plaintext, message_index })
}

/// Reads a NUL terminated UTF-8 string from C.
///
/// # Safety
/// `ptr` must be null or point to a NUL terminated string that stays valid
/// for the returned lifetime.
unsafe fn read_str<'a>(ptr: *const c_char) -> Result<&'a str, i32> {
    if ptr.is_null() {
        return Err(SEAM_ERR_NULL_ARGUMENT);
    }
    // SAFETY: the caller guarantees `ptr` is a valid NUL terminated string.
    let cstr = unsafe { CStr::from_ptr(ptr) };
    cstr.to_str().map_err(|_| SEAM_ERR_INPUT_NOT_UTF8)
}

/// Writes a successful result into the caller's out parameters.
///
/// # Safety
/// Both pointers must be non-null and valid for writes.
unsafe fn write_out(
    result: Decrypted,
    out_plaintext: *mut *mut c_char,
    out_message_index: *mut u32,
) -> i32 {
    // SAFETY: the caller checked both pointers are non-null and writable.
    unsafe {
        *out_message_index = result.message_index;
        *out_plaintext = result.plaintext.into_raw();
    }
    SEAM_OK
}

/// Runs `body` with panics turned into `SEAM_ERR_PANIC`.
fn guarded(body: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(SEAM_ERR_PANIC)
}

/// Decrypts one Megolm ciphertext with a vodozemac pickle and an explicit
/// 32-byte pickle key.
///
/// Only the vodozemac pickle format is accepted here, because the legacy
/// libolm fallback in the Dart SDK is keyed by the full user id, which a
/// 32-byte key cannot carry. Use `seam_megolm_decrypt_for_user` to get the
/// same two-step behaviour as the Dart SDK.
///
/// On success returns 0, sets `*out_plaintext` to a string the caller frees
/// with `seam_string_free`, and sets `*out_message_index`. On failure returns
/// a negative `SEAM_ERR_*` code and leaves the out parameters untouched.
///
/// # Safety
/// `pickle` and `ciphertext` must be NUL terminated strings, `pickle_key`
/// must point to `pickle_key_len` readable bytes, and both out pointers must
/// be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn seam_megolm_decrypt(
    pickle: *const c_char,
    pickle_key: *const u8,
    pickle_key_len: usize,
    ciphertext: *const c_char,
    out_plaintext: *mut *mut c_char,
    out_message_index: *mut u32,
) -> i32 {
    guarded(|| {
        if pickle_key.is_null() || out_plaintext.is_null() || out_message_index.is_null() {
            return SEAM_ERR_NULL_ARGUMENT;
        }
        if pickle_key_len != 32 {
            return SEAM_ERR_BAD_KEY_LENGTH;
        }
        // SAFETY: the caller guarantees both are NUL terminated strings.
        let (pickle, ciphertext) = match unsafe { (read_str(pickle), read_str(ciphertext)) } {
            (Ok(p), Ok(c)) => (p, c),
            (Err(e), _) | (_, Err(e)) => return e,
        };
        let mut key = Zeroizing::new([0u8; 32]);
        // SAFETY: `pickle_key` is non-null and points to 32 readable bytes.
        key.copy_from_slice(unsafe { std::slice::from_raw_parts(pickle_key, 32) });

        let Some(mut session) = unpickle_vodozemac(pickle, &key) else {
            return SEAM_ERR_BAD_PICKLE;
        };
        match decrypt_with(&mut session, ciphertext) {
            // SAFETY: both out pointers were checked non-null above.
            Ok(result) => unsafe { write_out(result, out_plaintext, out_message_index) },
            Err(code) => code,
        }
    })
}

/// Decrypts one Megolm ciphertext with a pickle read from the Dart SDK's
/// database, deriving the pickle keys from the account's user id exactly as
/// the Dart SDK does: the vodozemac pickle first, then the legacy libolm one.
///
/// Return values and out parameters are as for `seam_megolm_decrypt`.
///
/// # Safety
/// `pickle`, `user_id` and `ciphertext` must be NUL terminated strings and
/// both out pointers must be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn seam_megolm_decrypt_for_user(
    pickle: *const c_char,
    user_id: *const c_char,
    ciphertext: *const c_char,
    out_plaintext: *mut *mut c_char,
    out_message_index: *mut u32,
) -> i32 {
    guarded(|| {
        if out_plaintext.is_null() || out_message_index.is_null() {
            return SEAM_ERR_NULL_ARGUMENT;
        }
        // SAFETY: the caller guarantees all three are NUL terminated strings.
        let strings = unsafe { (read_str(pickle), read_str(user_id), read_str(ciphertext)) };
        let (pickle, user_id, ciphertext) = match strings {
            (Ok(p), Ok(u), Ok(c)) => (p, u, c),
            (Err(e), _, _) | (_, Err(e), _) | (_, _, Err(e)) => return e,
        };

        let Some(mut session) = unpickle_for_user(pickle, user_id) else {
            return SEAM_ERR_BAD_PICKLE;
        };
        match decrypt_with(&mut session, ciphertext) {
            // SAFETY: both out pointers were checked non-null above.
            Ok(result) => unsafe { write_out(result, out_plaintext, out_message_index) },
            Err(code) => code,
        }
    })
}

/// Frees a string returned by this library. Null is accepted and ignored.
///
/// # Safety
/// `ptr` must be null or a pointer returned through `out_plaintext` by this
/// library that has not been freed yet.
#[no_mangle]
pub unsafe extern "C" fn seam_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: the caller guarantees `ptr` came from `CString::into_raw`
        // in this library and is freed only once. Overwriting the bytes
        // first keeps the plaintext out of freed memory.
        unsafe {
            let owned = CString::from_raw(ptr);
            let mut bytes = owned.into_bytes();
            zeroize::Zeroize::zeroize(&mut bytes);
        }
    }));
}

#[cfg(test)]
mod tests;
