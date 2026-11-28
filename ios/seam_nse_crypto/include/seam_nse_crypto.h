/*
 * C interface of seam_nse_crypto, the Megolm decryption library linked into
 * Seam's iOS Notification Service Extension. Written by hand to match
 * src/lib.rs; keep the two in step.
 *
 * Every function returns SEAM_OK (0) on success or a negative SEAM_ERR_*
 * code. On failure the out parameters are left untouched. A plaintext
 * returned through out_plaintext is owned by the caller and must be released
 * with seam_string_free, which also overwrites it.
 */

#ifndef SEAM_NSE_CRYPTO_H
#define SEAM_NSE_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SEAM_OK 0
/* A required pointer argument was null. */
#define SEAM_ERR_NULL_ARGUMENT (-1)
/* The pickle key is not exactly 32 bytes long. */
#define SEAM_ERR_BAD_KEY_LENGTH (-2)
/* The pickle could not be read in any accepted format with the given key. */
#define SEAM_ERR_BAD_PICKLE (-3)
/* The ciphertext is not a base64 encoded Megolm message. */
#define SEAM_ERR_BAD_CIPHERTEXT (-4)
/* Bad signature or MAC, or a message index before the first known index. */
#define SEAM_ERR_DECRYPT (-5)
/* The decrypted plaintext is not valid UTF-8. */
#define SEAM_ERR_PLAINTEXT_NOT_UTF8 (-6)
/* A string argument is not valid UTF-8. */
#define SEAM_ERR_INPUT_NOT_UTF8 (-7)
/* The plaintext contains a NUL byte and cannot be returned as a C string. */
#define SEAM_ERR_PLAINTEXT_HAS_NUL (-8)
/* A panic was caught inside the library. */
#define SEAM_ERR_PANIC (-99)

/*
 * Decrypts one Megolm ciphertext with a vodozemac encrypted pickle of an
 * inbound group session and an explicit 32-byte pickle key. Only the
 * vodozemac pickle format is accepted.
 */
int32_t seam_megolm_decrypt(const char *pickle,
                            const uint8_t *pickle_key,
                            size_t pickle_key_len,
                            const char *ciphertext,
                            char **out_plaintext,
                            uint32_t *out_message_index);

/*
 * Decrypts one Megolm ciphertext with an inbound group session pickle as the
 * matrix Dart SDK stores it, deriving the keys from the account's user id the
 * way the Dart SDK does: the vodozemac pickle first, then the legacy libolm
 * pickle.
 */
int32_t seam_megolm_decrypt_for_user(const char *pickle,
                                     const char *user_id,
                                     const char *ciphertext,
                                     char **out_plaintext,
                                     uint32_t *out_message_index);

/* Overwrites and frees a string returned by this library. Accepts NULL. */
void seam_string_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif /* SEAM_NSE_CRYPTO_H */
