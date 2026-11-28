# seam_nse_crypto

Megolm decryption for the iOS Notification Service Extension (NSE).

A push from Seam's pusher carries only `room_id` and `event_id`. The NSE runs
without the Flutter engine, so it cannot ask the Dart Matrix SDK to decrypt
the event. This crate is a small Rust static library over
[vodozemac](https://crates.io/crates/vodozemac) that reads the inbound group
session pickles the Dart SDK stores and decrypts one `m.megolm.v1.aes-sha2`
ciphertext. `ios/Notification Service Extension/EventDecryptor.swift` does the
rest: it reads the account and the session from the app's SQLCipher database,
fetches the event and returns the fields a notification needs.

## Layout

| Path | What |
|---|---|
| `src/lib.rs` | C ABI: `seam_megolm_decrypt`, `seam_megolm_decrypt_for_user`, `seam_string_free` |
| `src/tests.rs` | Round trips through the C ABI with Dart-format and libolm-format pickles |
| `include/seam_nse_crypto.h` | Hand-written header; keep in step with `src/lib.rs` |
| `include/module.modulemap` | Lets Swift `import SeamNseCrypto` |
| `build_xcframework.sh` | Builds `SeamNseCrypto.xcframework` (git-ignored build product) |

## Rebuilding

```sh
ios/seam_nse_crypto/build_xcframework.sh   # release slices + xcframework
cd ios/seam_nse_crypto && cargo test       # host unit tests
```

The script builds `aarch64-apple-ios` and `aarch64-apple-ios-sim` with
`IPHONEOS_DEPLOYMENT_TARGET=17.0` (iOS 26 and later simulators are Apple
silicon only, so there is no x86_64 slice) and writes
`SeamNseCrypto.xcframework` next to it. Cargo's target dir is `target/` here.
A clean build takes about 19 s on an M-series MacBook Pro, an unchanged one
about a second, and two clean builds produce byte-identical `.a` files, so
the xcframework is not committed: the NSE target runs the script as a build
phase. The app build already needs a Rust toolchain, because
`flutter_vodozemac` compiles its Rust crate through cargokit during the pod
build.

## Pickle format and key

vodozemac is pinned to `=0.10.0`, the version `flutter_vodozemac` 0.9.0 locks
(`flutter_vodozemac-0.9.0/rust/Cargo.toml` and `rust/Cargo.lock`), so the
pickles are read by the same code that writes them.

- Storing: `KeyManager.setInboundGroupSession` creates the session with
  `vod.InboundGroupSession(session_key)` (session config version 1,
  `vodozemac-0.9.1/lib/src/api.dart:174-177`) and stores
  `inboundGroupSession.toPickleEncrypted(userId.toPickleKey())`
  (`matrix-16.0.4/lib/encryption/key_manager.dart:147`). That is
  `InboundGroupSession::pickle().encrypt(&key)` in Rust
  (`flutter_vodozemac-0.9.0/rust/src/bindings.rs:198-204`).
- Key: `toPickleKey` (`matrix-16.0.4/lib/encryption/utils/pickle_key.dart:7-15`)
  takes the user id's UTF-16 code units, keeps the low 8 bits of each
  (`Uint8List.fromList`), then zero pads or truncates to 32 bytes. For an
  ASCII MXID that is its bytes followed by zeros. `pickle_key_for_user_id` in
  `src/lib.rs` does the same, and `pickle_key_matches_dart_to_pickle_key`
  checks it against literal bytes, including non-ASCII and over-long ids.
- Loading: `SessionKey.fromDb` (`matrix-16.0.4/lib/encryption/utils/session_key.dart:91-104`)
  tries `InboundGroupSession.fromPickleEncrypted(pickle, key.toPickleKey())`
  and, if that throws, `fromOlmPickleEncrypted(pickle, utf8.encode(key))`,
  the legacy libolm pickle keyed by the full user id. `key` is the client's
  user id (`key_manager.dart:286`). `seam_megolm_decrypt_for_user` mirrors
  that order. `seam_megolm_decrypt` takes an explicit 32-byte key and reads
  only the vodozemac format, because a 32-byte key cannot carry the libolm
  fallback's key.

Return codes are in `include/seam_nse_crypto.h`: 0 on success, then
`-1` null argument, `-2` key not 32 bytes, `-3` bad pickle, `-4` ciphertext
not a Megolm message, `-5` decryption failed (signature, MAC or unknown
index), `-6` plaintext not UTF-8, `-7` input not UTF-8, `-8` plaintext has a
NUL byte, `-99` panic caught. Panics never cross the FFI boundary, the
release profile keeps unwinding for that reason, and the library logs nothing.

## Database

`MatrixSdkDatabase` stores each box as an SQLite table
`(k TEXT PRIMARY KEY NOT NULL, v TEXT)` named after the box
(`matrix-16.0.4/lib/src/database/sqflite_box.dart:35`). Map and list values
are `jsonEncode`d; strings, numbers and bools are stored with `toString()`
(`sqflite_box.dart:112-125`). Multi-part keys join their parts with `|`
(`TupleKey`, `matrix_sdk_database.dart:1777-1793`). Seam's file is
`<clientName>.sqlite` in the app group container
(`lib/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart:171-175`).

| Table (`matrix_sdk_database.dart`) | k | v |
|---|---|---|
| `box_client` (:100) | `homeserver_url`, `token`, `user_id` | plain strings, written by `storeClient` (:949-969) |
| `box_inbound_group_session` (:117-118) | session id only, no room (:558-565, :1257) | JSON object from `StoredInboundGroupSession.toJson` |

The session object (`matrix-16.0.4/lib/encryption/utils/stored_inbound_group_session.dart:43-54`)
has `room_id`, `session_id`, `pickle`, `sender_key`, and `content`,
`indexes`, `allowed_at_index`, `sender_claimed_keys`, which are themselves
JSON-encoded strings. `indexes` maps `key-<message index>` to
`<event id>|<origin_server_ts>` and is the Dart SDK's replay record
(`matrix-16.0.4/lib/encryption/encryption.dart:199-208`).

Seam passes `secureStorage` to `MatrixSdkDatabase.init` on iOS
(`builder.dart:144`), so the client values are also written to the keychain
item `client_data_<clientName>`, and `getClient` lets those win over
`box_client` (`matrix_sdk_database.dart:488-499`). `storeClient` writes both
in the same call (:914-990), and apart from restoring a database dump
(`importDump`, :1520-1527) nothing else writes `token` or `homeserver_url`
to the box, so the NSE reads `box_client`.

`EventDecryptor` follows the Dart SDK's decryption path
(`encryption.dart:165-275`): it requires `m.megolm.v1.aes-sha2` and a
`session_id`, rejects a row whose `session_id` differs, rejects a message
index recorded for another event, and copies the clear `m.relates_to` of the
encrypted event over the decrypted content (:263-265). It is also stricter in
two places: the stored `room_id` and any `room_id` in the decrypted payload
must match the push's room. It never writes to the database.

## Memory

The NSE is limited to about 24 MB. The static archives are about 5.8 MB per
slice, almost all of it object code the linker drops. A test executable that
calls `seam_megolm_decrypt_for_user` and links the device slice with
`-dead_strip` has 336 KB of `__TEXT` (including its own tiny `main`). At run
time one decryption holds a single session (a 128-byte ratchet and keys), the
event JSON and the plaintext.

## Integration

1. `ios/Notification Service Extension/EventDecryptor.swift` is in the
   extension target because the target takes every file of that folder.
2. The extension target has a Run Script build phase, "Build SeamNseCrypto",
   ahead of Compile Sources:
   ```sh
   "$SRCROOT/seam_nse_crypto/build_xcframework.sh"
   ```
   Its outputs are the two `libseam_nse_crypto.a` slices. The project has
   `ENABLE_USER_SCRIPT_SANDBOXING = NO`, which the script needs to write
   them.
3. The target links the static library by path, not as a listed
   `.xcframework`: Xcode reports a dependency cycle when a target lists an
   xcframework that one of its own script phases produces. The build
   settings are `LIBRARY_SEARCH_PATHS` per SDK (the `ios-arm64` and
   `ios-arm64-simulator` slice directories), `OTHER_LDFLAGS`
   `-lseam_nse_crypto`, and `SWIFT_INCLUDE_PATHS` at
   `seam_nse_crypto/include`, where the module map lives, so
   `EventDecryptor.swift` imports `SeamNseCrypto` with no bridging header.
4. `NotificationService.didReceive` ends with:
   ```swift
   Task {
       do {
           let event = try await EventDecryptor(database: database)
               .event(roomId: roomId, eventId: eventId)
           let sender = getUserFromDatabase(database: database, userId: event.senderId, roomId: roomId)?
               .content.displayname ?? event.senderId
           let text = event.isReaction
               ? event.relation?.key
               : (event.isEdit ? event.newContentBody : nil) ?? event.body
           if let text {
               bestAttemptContent.subtitle = sender
               bestAttemptContent.body = text
           }
       } catch {
           os_log("[SeamPush] Unable to load event: %{public}@", type: .error, String(describing: error))
       }
       contentHandler(bestAttemptContent)
   }
   ```
   The logged error is an `EventDecryptorError` case and holds no content.

## Verified and not

- `cargo test`: 17 tests pass, covering Dart-format and libolm-format
  pickles, message indexes, wrong user and key, bad key length, truncated
  pickles, garbage and tampered ciphertexts, non-UTF-8 input and plaintext,
  null pointers and a caught panic.
- `EventDecryptor.swift` with `SqlCipherDatabase.swift` type-checks with
  `swiftc -typecheck` against the iPhoneOS and iPhoneSimulator SDKs
  (Swift 5 and 6 modes), and an arm64 simulator executable linking the
  xcframework decrypts a vodozemac pickle and ciphertext when run with
  `xcrun simctl spawn` on an iOS 27 simulator.
- The extension target builds and links the library in a simulator debug
  build of the app.
- Not verified: the database reads and the HTTP fetch against a real Seam
  database and homeserver (no logged-in simulator database exists yet). A
  logged-in simulator with an encrypted room would settle it: copy its
  `<clientName>.sqlite` and check
  that `box_client` and `box_inbound_group_session` hold the values above.
- The NSE opens the database with `immutable=1`, which ignores a `-wal`
  file. I have not checked which journal mode the app's connection uses; if
  it is WAL, a session stored moments before the push may not be visible to
  the NSE yet.
