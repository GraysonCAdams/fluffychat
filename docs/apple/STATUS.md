# Seam on iOS and macOS: status

Branch `feat/apple`, cut from `feat/integration2`. Work tree: `~/Repos/seam-apple` on
Graysons-MacBook-Pro. Goal: iOS (built against the iOS 27 SDK) and macOS at feature parity with
Android and Windows, then kept there as features land.

## Build environment

| Item | Value |
|---|---|
| Xcode | 27.0 (27A266a), iOS 27.0 simulator runtime |
| Flutter | 3.47.9 through `fvm` (`.fvmrc`); run as `fvm flutter ...` |
| rsync | put `/usr/bin` first on `PATH`: Flutter's SwiftPM plugin copy fails with Homebrew rsync 3.4.4 (`mkdir ... SourcePackages ... No such file or directory`) |
| Signing | no identities on the Mac yet. iOS: simulator only. macOS: `FLUTTER_XCODE_CODE_SIGN_IDENTITY=- FLUTTER_XCODE_DEVELOPMENT_TEAM= FLUTTER_XCODE_CODE_SIGN_ENTITLEMENTS=<copy of DebugProfile.entitlements without keychain-access-groups>` in front of `fvm flutter build macos --debug` (that entitlement needs a development certificate) |
| Native tools | `brew install cmake ninja` (webcrypto's build hook); `rustup target add aarch64-apple-ios aarch64-apple-ios-sim` (vodozemac) |
| One build at a time | iOS and macOS builds share `.dart_tool` and the Swift package state; running both at once fails with unrelated errors |
| Test account | a throwaway Synapse in a container on the Mac, `seam-test-synapse`, listening on `127.0.0.1:8008` only, data and the two test users' fixture passwords in `~/.cache/seam-apple/synapse` (`alice`, `bob`; `seed.py` has bob open a chat with alice and send messages). Sign in on the simulator with server `http://localhost:8008`. No bridges, so merged contacts and network colours are not covered |
| Driving the app | build with `--dart-define=SEAM_DEV_CONTROL=true` and use `tools/devctl/devctl.py` with `DEVCTL_FILE` pointing at the app's `devctl.json` (docs/dev-control.md). The simulator is headless and `screencapture` has no Screen Recording permission over ssh, so this is also how macOS screenshots are taken |
| Git | the Mac has no GitHub credentials: commit here, fetch from the laptop over ssh, push there |

## Phases

1. **Builds and runs.** First iOS simulator and macOS debug builds; fix what fails.
2. **Identity.** Bundle ids `dev.threeonetwo.seam` (+ `.share`, `.nse`), app group
   `group.dev.threeonetwo.seam`, team `8MRX27GBLK`, Firebase plist and FluffyChat fastlane removed,
   purpose strings, icons, URL schemes, export compliance flag.
3. **Push and notifications.** APNs token channel, pusher registration, Notification Service
   Extension (decrypt, attach media, communication notifications with sender avatars and group
   images), actions (reply, mark read, copy code).
4. **Native conventions.** Data detectors, haptics for the peek and effects, share sheet and
   share extension, photo picker, Dynamic Type, macOS menu bar, Dock badge, window behaviour.
5. **Parity sweep.** Walk every feature in the gap table on a simulator and on the Mac;
   screenshots at each milestone.
6. **Maintenance.** Merge `feat/integration2` regularly; each new Android/Windows feature gets an
   Apple row in the gap table.

## Open decisions

- Push delivery (gateway). Asked 2026-11-27; native work assumes a Sygnal gateway with an APNs key.

## Gap table

From a read of the code at `7df544eb1` (nothing here is verified on a device unless the Log says
so). "Gate" is the Dart platform check that keeps the feature off Apple platforms today.

### Build blockers found on the first builds

| Blocker | Fix on this branch |
|---|---|
| `opus_codec_ios` / `_macos` keep `opus.xcframework` outside their Swift package | vendored under `third_party/`, framework moved inside the package |
| No `ios/Podfile`; Flutter's template names a `RunnerTests` target that does not exist | committed `ios/Podfile` |
| `ffmpeg_kit_flutter_new_min` (through `whisper_ggml`) has no arm64 simulator slice | vendored Android only under `third_party/` |
| `webcrypto` does not link for the x86_64 simulator | `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` in `ios/Flutter/*.xcconfig` |
| Runner at iOS 15.0 while Swift packages need 15.6, extension at 18.5 | all iOS targets at 17.0 |
| No `macos/Podfile`; the pub.dev `opus_codec_macos` framework lost its `Versions/Current` links | committed `macos/Podfile`; framework rebuilt as a versioned bundle in `third_party/` |

### Absent on Apple platforms, native work needed

| Area | Android / Windows today | iOS today | macOS today | Apple route |
|---|---|---|---|---|
| Push delivery | UnifiedPush | **app side built**: `ApnsTokenChannel.swift`, `lib/utils/apple_push.dart`, `setupApplePush`; inert until `SEAM_PUSH_GATEWAY_URL` is set; not yet run against APNs | none (local only) | APNs token channel, `setupPusher` to the gateway |
| Notification content | `MessagingStyle`, `Person`, sender icons | **decryption built**: `ios/seam_nse_crypto` + `EventDecryptor.swift` set sender and text; not yet run against a real database; communication notifications still to do | plain text while a window is open | decrypt in the Notification Service Extension; `INSendMessageIntent` communication notifications |
| Notification actions | reply, mark read, mute, copy code | none | none | `UNNotificationCategory`, `UNTextInputNotificationAction` |
| Photos in notifications | Android | none | none | `UNNotificationAttachment` from the extension |
| Group collage icon | Android shortcut icon, Windows toast | room avatar only | none | collage rendered for the intent's `INImage` |
| Conversation shortcuts, direct share | Android | none | none | `INInteraction` donation, share suggestions |
| Unread badge | Windows taskbar | extension sets it | **seen**: against the local test server the Dock badge read `1` with one unread chat and cleared when the chat was read from another session (`_updateTaskbarBadge` in `lib/widgets/matrix.dart`) | `NSApp.dockTile.badgeLabel` from sync |
| Effect haptics | `effect_haptics.dart` (Android channel) | **built**: `ios/Runner/EffectHaptics.swift` answers the same channel; not yet felt on a device | n/a | Core Haptics patterns behind the same channel |
| Voice transcripts | whisper (`isAndroid \|\| isWindows`) | hidden | hidden | Speech framework, on device |
| Contacts import | Android | hidden | hidden | `flutter_contacts` gate plus purpose string |
| Spell check | Android and Windows bridges | Flutter default (`UITextChecker`) | none | `NSSpellChecker` |
| Context menus | Windows native menu | Flutter menu | Flutter menu | `SystemContextMenu` on iOS, `NSMenu` on macOS |
| Chat windows | Windows | n/a | hidden | one `NSWindow` per chat |
| Stay running, launch at login | Windows tray | n/a | quits with the last window | keep running after close, `SMAppService`, `NSStatusItem` |
| Menu bar | n/a | n/a | **built**: `lib/widgets/mac_menu_bar.dart` (Settings, New chat, New group, Edit commands, Chats, Window); signed in, Settings, New chat, New group and Chats each went to their route when clicked through accessibility; File/Edit/View/Window/Undo/Redo titles are English only | `PlatformMenuBar` |
| Title bar with search | `WindowsChrome` | n/a | standard | unified `NSToolbar` title bar |
| Data detectors | Android `TextClassifier`, Windows Seam's own (`lib/utils/data_detectors`, branch `feat/data-detectors-v3`) | **built**: `ios/Runner/DataDetectors.swift` answers `chat.fluffy.fluffychat/data_detectors` with `NSDataDetector` (Maps, Call, FaceTime, Create Event, Show in Calendar); seen in a chat on the simulator: address, date, phone and flight are underlined, the tap menu lists Create Event and Show in Calendar before Seam's Copy, and Create Event opens the system sheet on the right day and hour. Call, FaceTime and Maps not exercised (the simulator has no phone). Relative dates resolve from today, titles are English, no icons | Seam's own Dart detector | `NSDataDetector` behind that channel (contract in `data_detector_platform.dart`) |
| Share-to | Android intents (`SEND`, `SEND_MULTIPLE`, any type) | **built**: Seam's own `ShareViewController` copies every attachment as a file into the app group's `SharedItems` folder and a `SUBQUERY` activation rule takes any number of data, link or text items. Seen on the simulator against the local test server: 12 photos from Photos list Seam, are staged on the New chat screen, and arrive on the server as 12 `m.image` messages. Not yet seen: a contact card or pass, slow-motion video, a physical device | none: no share extension, no `CFBundleDocumentTypes`, so Seam is absent from the Share menu and Open With | macOS: share extension plus document types |
| Push settings row | UnifiedPush distributors | hidden | hidden | APNs status row |

### Present through a fallback, below parity

Video poster frames (macOS gets none), gallery picker and camera (macOS is file picker only),
plain `HapticFeedback` calls (fine on iOS, nothing on macOS), macOS keychain access group is empty
in both entitlements files.

### Checked on the first run

`loadDynamicPrimaryColor()` does not stop startup on iOS: the app reaches the intro screen on the
iOS 27 simulator (2026-11-27). No change made there.

### No gap (platform-neutral Dart)

Merged contacts, network bubble colours, effect visuals and replay, chat peek, search, chat list,
reply thumbnails, link previews, stitch loader, settings, About dialog, emoticons, mention pills,
typing indicators, read status, app lock, one-time-code detection.

## Log

- 2026-11-27: repo cloned, Flutter 3.47.9 installed. First green iOS simulator build and first
  green macOS debug build; app launches on the iPhone 18 Pro simulator (iOS 27.0). Seam identity
  applied to both projects. `feat/integration2` @ 4a52f278c (calls removed) and `feat/dev-control`
  merged in.

- 2026-11-27 (later): `feat/integration2` @ 587616abb merged. APNs token channel, Core Haptics
  effect haptics, Seam icons and launch screen, megolm decryption in the notification extension.
  All compile; none of the four has run with a signed-in account or on a device.

- 2026-11-27 (night): macOS menu bar and Dock badge wiring; macOS debug build green. `dart analyze`
  cannot run here: the `dart_code_linter` analyzer plugin fails to resolve (`version "latest"`).

- 2026-11-28 (overnight): iOS data detectors (`NSDataDetector` behind the shared channel), Seam's own
  share extension (12 photos from Photos arrive as 12 files), pusher app ids per APNs environment
  (`dev.threeonetwo.seam.ios` and `.ios-sandbox`), and the layered icon `ios/Runner/AppIcon.icon`
  (Icon Composer format: `brand/apple/icon-composer` layers at scale 1024/432 on a cobalt fill,
  dark and tinted left to the system). The iOS 27 simulator Home Screen shows the layered icon; the
  flat `AppIcon.appiconset` stays as the icon for iOS 17 and 18. Simulator taps and screenshots of
  other apps come from a scripted XCUITest driver kept outside the repo
  (`~/.cache/seam-apple/uidriver`).

- 2026-11-28 (overnight): privacy manifests `ios/Runner/PrivacyInfo.xcprivacy` and
  `ios/Seam Share/PrivacyInfo.xcprivacy`: no tracking, no collected data types, `UserDefaults`
  reasons CA92.1 (the app's own) and 1C8F.1 (the app group). The collected data answer must match
  the App Store privacy labels (stores session to confirm). macOS has none yet.

- 2026-11-28 (overnight): signed in on the simulator against a local test homeserver, which
  unblocked in-app checks without the store reviewer's account. Seen working there: sign-in with a
  password, chat list with unread count, data detectors and Create Event, 12 shared photos sent.
  Found on the way: the New chat screen's recent conversation rows carry no accessibility label
  (the driver could not find "Group with bob" by name; VoiceOver users likely cannot either).

- 2026-11-28 (overnight): Mac app signed in to the local test server as the second user (ad hoc
  signed, no keychain group). Menu items and Dock badge seen working. Emoji button: it reaches
  `TSMLaunchCharacterPalette`, which answers `okToLaunch: 0`; the system's own Edit > Emoji &
  Symbols gets the same refusal in this session, where another app (a KVM viewer) holds the front
  and Seam cannot be made frontmost over ssh. So the Character Viewer and the emoji landing in
  the composer still need a look at the Mac in person.

## Needs Grayson

1. Push gateway decision (asked).
2. A signing identity on the Mac (Xcode signed in to the 312.dev team, or development certificates
   made through the App Store Connect API): needed for the macOS keychain, any run on a real
   iPhone, push, and app groups on device.
3. An account to sign in with on the simulator and the Mac (the only test account is the store
   reviewer's `@seam-review:matrix.org`, which has no bridges).
