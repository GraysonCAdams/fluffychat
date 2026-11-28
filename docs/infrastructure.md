# Where Seam's infrastructure runs

Seam must not use the Hetzner box; Seam infrastructure lives in the 312.dev Cloudflare account.

That also rules out Scrolly's Cloudflare account and every other Scrolly resource ("do not share
scrolly resources", Grayson, 2026-11-28). The 312.dev zone currently sits in Scrolly's account, so
anything Seam hosts waits for a Seam-only account.

The push gateway is a Cloudflare Worker in its own repo, `~/repos/seam-push` on GRAYTHINKPAD. It
routes by pusher app id:

| app id prefix | goes to |
|---|---|
| `dev.threeonetwo.seam.ios.` | APNs production (`api.push.apple.com`) |
| `dev.threeonetwo.seam.ios-sandbox.` | APNs sandbox (`api.sandbox.push.apple.com`) |
| `dev.threeonetwo.seam.` | FCM, project `seam-312dev` (Android release) |
| `chat.fluffy.fluffychat.` | FCM, project `seam-312dev` (Android debug and profile) |

The iOS pushkey is the APNs device token in lowercase hex; base64 is accepted too. The build gets the
gateway URL from `--dart-define=SEAM_PUSH_GATEWAY_URL=<origin>/_matrix/push/v1/notify`.
