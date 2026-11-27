# Before Seam's first Play release

Everything that must be true before Seam is published on Google Play, in the order to do it. Each
line names what is owed; delete a line once it is done, with the date in the commit.

The listing itself is `README.md` beside this file. The Play Console's questionnaires (data
safety, content rating, target audience, permission and foreground-service declarations) are
answered in the seam-site repository, `content/legal/play-declarations.md`. This file points at
both and does not repeat them.

## 0. Decide first

These are the owner's calls, and two of them cannot be undone after the first upload.

- **Free, for good.** Play's Developer Distribution Agreement (3.7): an app first offered free
  stays free. Seam is planned as free; confirm before the first upload.
- **Push: UnifiedPush only (the default) or add Firebase.** See "Push" below. Changing it later
  changes the privacy policy and the data safety form.
- **Data safety posture and target audience.** `play-declarations.md` recommends "collected, not
  shared" and 18+, and gives the alternatives.
- **Features Play may question** (see "Kept features that need a declaration" below). Each
  needs a declaration or a ruling.

## 1. Developer account

1. Use (or create) a Play Console developer account and finish Google's identity verification.
2. A personal account created recently must run a closed test with enough testers for 14 days
   before it can publish to production. Check the current numbers in the console; this was not
   verified against Google's pages.

## 2. Create the app

In Play Console, Create app: name **Seam**, default language English (United States), **App**,
**Free**, and accept the declarations. The package name is fixed by the first upload: it is
`dev.threeonetwo.seam`, the release build's `applicationId` (see "Release identity").

## 3. Upload key and Play App Signing

Play App Signing is on by default for a new app: Google holds the key that signs what users
install, and you sign uploads with an **upload key** that you keep. Nothing in this repo creates
or holds that key.

1. Create the upload key on a trusted machine, outside the repo:

       keytool -genkeypair -v -keystore ~/seam-upload.jks -storetype JKS \
         -keyalg RSA -keysize 2048 -validity 10000 -alias upload

2. Back it up (on a Mac, the 1Password "MCP" vault; never in git or plain text on disk). Losing
   it is recoverable through Play support's upload-key reset, but slowly.
3. Point the build at it, either with `android/key.properties` (gitignored, as are `*.jks` and
   `*.keystore`):

       storeFile=/absolute/path/to/seam-upload.jks
       storePassword=...
       keyAlias=upload
       keyPassword=...

   or with environment variables, which fill any value the file leaves out:
   `SEAM_UPLOAD_STORE_FILE`, `SEAM_UPLOAD_STORE_PASSWORD`, `SEAM_UPLOAD_KEY_ALIAS`,
   `SEAM_UPLOAD_KEY_PASSWORD`. A relative `storeFile` is resolved against `android/app`.
   `android/app/build.gradle.kts` stops any release build that has no upload key, so an unsigned
   bundle never gets as far as the console.
4. On the first upload, accept Play App Signing with a Google-generated app signing key.

## 4. Build the bundle

From the repo root, on the commit you mean to ship:

    flutter build appbundle --release

The bundle is `build/app/outputs/bundle/release/app-release.aab`. The version comes from
`pubspec.yaml` (`version: 2.11.6+3580`, inherited from upstream); to give Seam its own version
name without lowering the build number the owner's debug install upgrades from, pass
`--build-name=1.0.0` and keep `--build-number` at or above the pubspec's.

Then, for the AGPL (section 6): tag that commit (`git tag seam-v<version>`) and push the tag to
`github.com/GraysonCAdams/fluffychat`, so the source of every published build stays reachable
from the link in the listing and the About screen.

Before the first upload, check the merged manifest of that build against
`play-declarations.md`'s permission section. "Permissions in the release build" below is the list
as of this commit.

## 5. Internal testing first

1. Testing, Internal testing: create a release, upload the AAB, paste `copy/release-notes.txt`.
2. Add testers by email list and install Seam from the opt-in link.
3. The Play app is `dev.threeonetwo.seam` and installs beside the owner's everyday build
   (`chat.fluffy.fluffychat.fork`); neither replaces the other.
4. Check on a test device: sign in with SSO on a homeserver (the redirect uses the release scheme
   `dev.threeonetwo.seam.auth`), push through a UnifiedPush distributor such as ntfy, attaching
   photos and videos from the composer's Gallery button (it opens the system Photo Picker, which
   asks for no permission), and contacts in New Chat.
5. Then a closed test if the account needs one (step 1), then production.

## 6. Store listing and App content

1. **Main store listing**: paste `copy/`, upload `icon-512.png`, `play/feature-graphic.png` and
   the phone screenshots (`play/screenshots/README.md`). Run `node android/store/check.js` first.
   Category Communication; contact email, website and privacy policy as in `README.md`.
2. **Privacy policy**: `https://seam.312.dev/privacy`. It must be live and public before
   submitting.
3. **App access**: `copy/play-app-access-instructions.txt`, with the placeholders replaced in the
   console by the review account's details (never committed). Create the two matrix.org review
   accounts described in `play-declarations.md` first.
4. **Ads**: No.
5. **Content rating, Target audience, Data safety, Government, Financial, Health, News,
   Advertising ID**: as answered in `play-declarations.md`.
6. **Account deletion URL**: Seam lets users register on a homeserver, so Play wants a web page
   that explains deletion. Publish one on seam.312.dev (a `#delete` anchor in the privacy policy or
   a `/delete-account` page) saying that Settings, Security, Delete account deactivates and erases
   the account on its homeserver.
7. **Permission declarations**: see the next section.

## Kept features that need a declaration

These stay in the Play build, and each is a declaration or a decision. Seam has no voice or video
calls and attaches media only through the system Photo Picker, so Play's foreground service,
full-screen intent and photo and video permission declarations do not apply to it.

| Feature | What Play asks | Status |
|---|---|---|
| Contacts in New Chat (`READ_CONTACTS`) | From 2027-01-27 broad contacts access is restricted to apps whose core function needs it; others must use the Contact Picker. | Kept. The request row now says contacts stay on the device and are matched there. Before 2027-01-27, argue the core use or move to the Contact Picker. |
| Conversation shortcuts to Google (`core-google-shortcuts`) | Not a Play form; a privacy question. | Left out of the release build only (`android/app/build.gradle.kts`): shortcuts, share targets and bubbles use androidx.core's ShortcutManagerCompat and do not need it. Debug and profile builds keep it. |
| Bridge features for the owner's own server | Not a Play form. The network ids `imessage`, `gmessages`, `telegram`, `linkedin`, `xbox` are compiled in (`lib/utils/bridge_provisioning.dart`, `lib/utils/new_chat/new_chat_people.dart`, `lib/utils/merged_contacts/network_colors.dart`), with iMessage first in the network picker. | Kept. The provisioning calls go through `/_matrix/client/unstable/net.graysons.bridge/`, a proxy that exists only on the owner's homeserver, so for anyone else New Chat's network lookup and the start-chat-on-a-network flow find no bridges and do nothing. None of it appears in the listing. |

## Push

The Play build is **UnifiedPush only**. Firebase Cloud Messaging is not compiled in
(`scripts/add-firebase-messaging.sh` is not run), and the FCM gateway setting is empty by
default, so the app never contacts upstream's `push.fluffychat.im`. A user installs a
distributor app (ntfy or another), and the homeserver sends notifications through that
distributor's gateway or the UnifiedPush project's public one at `matrix.gateway.unifiedpush.org`.
This matches the privacy policy: the developer runs no server.

The trade-off: a user with no distributor gets no notifications while Seam is closed, and sees a
notice saying push is unavailable. Most people on Play have Google services and expect push to
just work.

To add FCM later (a human step, and a policy change):

1. Create a Firebase project of your own and an Android app in it for `dev.threeonetwo.seam`;
   put its `google-services.json` in `android/app/` (it is applied automatically when present).
2. Run your own Matrix push gateway with that project's credentials (Sygnal, or upstream's
   AGPL `fluffygate`). Never point at `push.fluffychat.im`.
3. Build with `scripts/add-firebase-messaging.sh` applied and
   `--dart-define=SEAM_PUSH_GATEWAY_URL=https://<your gateway>/_matrix/push/v1/notify`.
4. Update the privacy policy (a server you run now sees room ids, event ids and unread counts,
   and Google processes the token) and the data safety form before shipping that build.

## Release identity

Release builds are the Play app. Debug and profile builds stay the owner's everyday install, which
keeps upgrading in place, logged in, with its pushers and notification settings.

| | Release (Play) | Debug and profile |
|---|---|---|
| `applicationId` | `dev.threeonetwo.seam` | `chat.fluffy.fluffychat.fork` |
| Label | Seam | Seam |
| Deep link scheme | `dev.threeonetwo.seam://chat/` | `im.fluffychat://chat/` |
| SSO redirect scheme | `dev.threeonetwo.seam.auth:/login` | `im.fluffychat.auth:/login` |
| Push app id (pusher) | `dev.threeonetwo.seam.<device>` | `chat.fluffy.fluffychat.<device>` |
| Notification channel id | `fluffychat_push` (internal, never shown) | the same |
| Sign-in server list | none: the user types a homeserver | public list, matrix.org preselected |
| Signing | upload key (step 3) | debug key |

The Gradle side is `android/app/build.gradle.kts` (the variant API sets the debug and profile id;
manifest placeholders carry the schemes); the Dart side is `AppConfig.isPlayRelease` in
`lib/config/app_config.dart`. The Kotlin namespace `chat.fluffy.fluffychat` is internal and stays.
iOS, macOS, Linux and Windows still carry upstream's bundle ids and schemes; they are not
published and need the same treatment before any other store.

## Permissions in the release build

From the manifest inside the signed release bundle built on 2026-11-27 (versionCode 3581, read
with `aapt2 dump xmltree` from `base/manifest/AndroidManifest.xml`).
Package `dev.threeonetwo.seam`, label Seam. No `AD_ID`, SMS, call log, accessibility,
`QUERY_ALL_PACKAGES`, `MANAGE_EXTERNAL_STORAGE`, exact alarm or background location permission,
no `READ_MEDIA_*` or storage permission, no `USE_FULL_SCREEN_INTENT`, and no foreground service
type other than `shortService`.

| Permission | From | Why | Play form |
|---|---|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | app, plugins | Talking to the homeserver; connectivity checks | none |
| `VIBRATE`, `WAKE_LOCK` | app | Notification vibration; finishing work after a push | none |
| `RECORD_AUDIO` | app | Voice messages | none (runtime) |
| `CAMERA` | app | Taking a photo or video to send, QR codes | none (runtime) |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | app | Sharing a location once, on the user's action | none; no background location |
| `READ_CONTACTS` | app | Contacts in New Chat, matched on the device | data safety; contacts policy from 2027-01-27 |
| `USE_BIOMETRIC`, `USE_FINGERPRINT` | app, plugin | Unlocking the app lock | none |
| `POST_NOTIFICATIONS` | plugins | Notifications | none (runtime) |
| `FOREGROUND_SERVICE` | app | `flutter_foreground_task` service, type `shortService` only | none (short service is not a declared type) |
| `RECEIVE_BOOT_COMPLETED` | plugins | Restoring scheduled notifications after a reboot | none |
| `dev.threeonetwo.seam.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | androidx | Signature permission private to the app | none |
| Launcher badge permissions (Samsung, HTC, Sony, Huawei, Oppo, Apex and others) | badge plugin | Unread count on the launcher icon | none |

Removed from the manifest because nothing starts them: `light_compressor_v2`'s
`CompressionForegroundService` with `FOREGROUND_SERVICE_DATA_SYNC` (the app never asks it for
background compression) and `geolocator`'s `GeolocatorLocationService` (the app takes one-shot
positions), and the `camera`, `microphone` and `mediaProjection` types on the
`flutter_foreground_task` service (only ever started as `shortService`).
`core-google-shortcuts` and its `shortcut_listener_impl` are absent from the
release build and present in debug and profile, as intended.

## Legal review: what a public binary needed

From the legal report (sections 3.3, 4, 5 and 9). "Done" means done in this repo.

| Requirement | Status |
|---|---|
| New name and icon everywhere user-facing | Done (brand commits; translations in this branch) |
| New application id under a domain the owner controls | Done for Android release: `dev.threeonetwo.seam` |
| URL schemes that do not collide with upstream | Done for Android release |
| Mascot and banner out of the binary | Done (not bundled; files remain in the GitHub fork's tree, which the report allows) |
| Branded strings in every language | Done |
| Upstream store metadata replaced | Done: `android/fastlane/metadata` removed, this kit added |
| No upstream push gateway or Firebase project | Done for Android: UnifiedPush only, empty gateway default. iOS's `GoogleService-Info.plist` is upstream's; iOS is not published |
| OIDC client metadata (site, logo, privacy, terms) | Done: seam.312.dev URLs. The logo URL `https://seam.312.dev/icon-512.png` must exist when the site goes up |
| Issue tracker, update check, homeserver list | Done earlier: the fork's own repo. The release build fetches no homeserver list |
| Donation and tutorial links | Done: ko-fi tutorials and their buttons removed; donation entry removed earlier |
| Unused `crash.fluffy.chat` endpoint | Done: removed |
| Invite links naming upstream's client | Done: `?client=im.fluffychat` dropped |
| Own privacy policy | Written in seam-site; must be live at `https://seam.312.dev/privacy`. Human step |
| About screen: copyright, AGPL, no warranty, source link | Done earlier (About dialog) |
| Source link in the listing | Done: in `copy/description.txt`, enforced by `check.js` |
| A tag per published build | Human step (step 4) |
| Upstream release workflows that publish under upstream's identity | Done: `release.yaml` and `main_deploy.yaml` removed |
| Play declarations: contacts | Human step (step 6), text in `play-declarations.md` |
| Listing free of other companies' brands (spectrum a or b) | Done: `check.js` enforces it |
| Dependency licence check | Human step: `dart run license_checker check-licenses -c licenses.yaml --problematic` before each release |
| Decide free or paid before the first release | Owner decision (section 0) |
| Trademark search for "Seam" | Not done; worth a USPTO and EUIPO search before investing in the name |
