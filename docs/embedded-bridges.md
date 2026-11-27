# Bundling a server and bridges into Seam (shelved)

Status: explored on 2026-11-26 and shelved. Nothing was built. This records what was found so the
question does not have to be researched again.

The idea: people who cannot self-host get the Matrix server and the network bridges inside Seam
itself, on Android and Windows, instead of on a server like `d.graysons.network`.

## What is technically possible

- **Server.** Synapse is too heavy to embed. A small Rust homeserver (conduwuit or its successor
  tuwunel: one program, built-in database, Apache-2.0) or Dendrite (Go) would fit on a phone and on
  Windows.
- **Bridges.** The mautrix bridges are Go, built on mautrix-go's `bridgev2`, with each network a
  connector. Running "in the app" still means compiling Go for the device (Android arm64, Windows
  x64); mautrix only publishes Linux and macOS programs. The workable form is one Go shared library
  (`.so` / `.dll`) holding several connectors, loaded into Seam's process over FFI like the Rust
  encryption library. `bridgev2` talks to Matrix through a replaceable connector layer, so the
  bridges might even plug into Seam's own storage with no homeserver; how pluggable that layer is
  was not verified.
- **iMessage cannot be embedded.** It needs Apple hardware for registration (the macoun setup).
- **Downloading bridges as drivers** works on Windows (catalogue of signed builds, fetched and
  updated on demand). On Android it does not: since Android 10 an app cannot execute a program it
  downloaded into its own storage, and Google Play forbids downloading executable code from outside
  Play. Android bridges would have to ship inside the app package (or as Play on-demand modules).

## Hard problems

- **Always running.** A bridge only receives messages while it runs. On Android that means a
  permanent foreground service and notification, and battery cost. Windows is the natural host:
  plugged in and always on.
- **Several devices.** Two devices each hosting their own server means two inboxes. Realistic shape:
  one host per account, other devices connect to it, which needs a tunnel or relay to reach a home
  PC from the phone.
- **Moving between hosts.** A Matrix account's address includes its server name (`@you:server`) and
  Matrix cannot yet move accounts between servers. Moving works only if the server name is stable
  and separate from the machine (own domain or a hosted subdomain), the server software is the same
  everywhere, and the old host stops before the new one starts. Moving to Synapse is not realistic:
  there is no converter from the embedded servers' databases.

## Why it was shelved: distribution

Licensing is not the obstacle. Seam is AGPL-3.0 (inherited from FluffyChat); the bridges and
libsignal are AGPL-3.0, mautrix-go and whatsmeow MPL-2.0, tuwunel Apache-2.0, all compatible, with
the source-publishing duties Seam already has.

The obstacle is where it could be published. Google Play prohibits apps that access third-party
services in ways those services forbid, Meta, Google and Apple can file takedown complaints, and
unofficial WhatsApp clients have been removed from Play before. Users would also carry the account
ban risk themselves. F-Droid accepts the licenses but requires every part (Go and Rust included) to
build from source on its servers. Direct download on Windows has no gatekeeper. The likely split, a
store-friendly client plus a fuller build distributed directly, was judged not worth it for now.
