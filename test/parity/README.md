<!--
SPDX-FileCopyrightText: 2026 Grayson Adams

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Parity goldens

The Seam website ([seam.312.dev](https://seam.312.dev), repo
`GraysonCAdams/seam-site`) shows HTML recreations of this app's screens.
This folder renders the same screens with the app's real widgets, without a
phone, so the site can diff its HTML against them. The site's
`pnpm parity:sync` pulls this branch, runs the harness, copies
`goldens/*.png` and compares its recreations with them.

## Rule

Any change to a widget listed in the site's component map (seam-site
`docs/ARCHITECTURE.md`, section 5.2) is followed by regenerating the goldens
here and running `pnpm parity:sync` in the site, so its recreation is checked
against the new look.

## Running

```sh
flutter test test/parity --update-goldens   # rewrite goldens/*.png
flutter test test/parity                    # compare against them
```

Add `--dart-define=PARITY_LOG=true` to print each HTTP request the fake
server answers and how far each screen got.

## What it renders

Each `fixtures/<screen>.json` comes from the site (its `pnpm parity:sync`
refreshes them; the `Scene` type in seam-site `src/ui/types.ts` describes the
fields) and becomes `goldens/<screen>.png`. The phone screens are exactly
1080 x 2410 pixels: the
reference phone's screen at 411.43 x 918.1 logical pixels and a density of
2.625, with its status bar (65.7) and navigation bar (36.2) as system
padding. The theme is the app's own (`FluffyThemes.buildTheme`), dark, with a
seed of HCT hue 268.4, which gives the phone's accents (primary `#B0C6FF`,
primaryContainer `#18438F`, secondaryContainer `#404659`; a test checks
them). Text uses the app's own font, Google Sans Flex (the theme sets it for
all text), with Roboto Mono Bold for initials and the Material icons, so
glyphs are real, not test boxes; a test checks that text set in the theme
really draws in Google Sans Flex.

Every screen is the app's real page, not a copy of its layout:

| Screen | Page pumped | What the harness supplies |
|---|---|---|
| `chat-list` | `ChatList` | rooms, pins, the unread chats below the fold behind the "N unread" chip, the bridges' spaces behind the "All" menu |
| `chat-list-selected` | `ChatList` | as above, then a long press on the selected row and the fixture's scroll |
| `chat-list-search` | `ChatList` | types the query; the fake server answers the message search with the fixture's hits and leaves its next page pending, as the phone showed it |
| `network-menu` | `ChatList` | taps the "All" chip; the menu's rows are the spaces the fixture names |
| `chat-dm` | `ChatPage` | a direct chat on one network, its timeline and its bridge space |
| `chat-dm-linked` | `ChatPage` (merged contact) | a room per network merged into one contact, so the network switcher shows |
| `new-chat` | `NewPrivateChat` | the contacts offer (through `NewChatDelivery`) |
| `new-chat-results` | `NewPrivateChat` | the results as existing chats (merged where they span networks), then types the query |
| `desktop` | `WindowsChrome` over `TwoColumnLayout`: `ChatList` (with its spaces rail) and `ChatPage` (merged contact) | the rooms of `chat-list` and `chat-dm-linked` in one client, the linked contact open |

`desktop` has no fixture of its own: it is the Windows app's window, built
from the `chat-list` and `chat-dm-linked` fixtures. It is 2560 x 1600
pixels, a window of 1280 x 800 logical pixels at a density of 2, with no
system padding, in the same theme and fonts as the phone screens. The
window is composed as the app builds it on Windows: the title bar
(`WindowsChrome`, `lib/utils/windows_shell_ffi.dart`: app tile and name,
the search field in the middle, the account button and the window
buttons) over the two columns the app's router shows at this width, the
chat list (whose own header hides while the title bar holds the search)
and the linked contact's conversation. The linked contact's rooms come
first after the pinned chats, so its row shows as the active chat. The
test runs as Windows (`PlatformInfos.debugOperatingSystem` and Flutter's
target platform), so times print on the 12-hour clock: off Android the app
picks the clock from the language (`use24HourFormat` in
`lib/utils/date_time_extension.dart`), and English gets 12 hours, where the
phone screens follow the phone's 24-hour setting.
The window buttons ask `window_manager` whether the window is maximized;
with no plugin behind it the app logs the failure and draws the maximize
button.

What stands in for the rest of the app:

- `ParityClient` (`harness.dart`) is a matrix `Client` with an in-memory
  database that looks logged in and synced. Its HTTP client is a fake server:
  a message photo that names a demo picture gets `images/<name>.png` (drawn
  by the site's `scripts/make-demo-images.py`, copied here by
  `pnpm parity:sync`); any other media request gets a flat grey picture
  (`#353535`, in the shape a message photo asks for), the own profile is "Robin" with a picture, the directory
  and message searches answer from the fixture, anything else is not found.
  A fixture's `picture: true` therefore shows as a plain disc, never a photo.
- `ParityRoom` opens a timeline of the events the fixture lists instead of
  asking a server, and keeps read markers and typing local.
- `ParityMatrix` stands in for the app's `Matrix` widget with that client.
- The plugins the app starts on Android (shared intents, shortcuts, calls,
  managed configuration) get channels that answer nothing.
- Times are set relative to today so the list prints the fixture's labels
  ("21:16" today, "Tue" for the last Tuesday). A "Tue" label shows a date
  instead during the first week of January.

One change in `lib/` serves this: `PlatformInfos.debugOperatingSystem`
(`lib/utils/platform_infos.dart`, `@visibleForTesting`). The harness sets it
to `android` so the app takes its Android code paths (for example, it reads
the 24-hour clock setting from the system) while the test runs on a desktop,
and to `windows` for `desktop`. It is null in the app.

## Animations

`animations_test.dart` (helpers in `anim_recorder.dart`) drives the app's
real widgets through the animations the site reproduces and records each
one into `anim/<name>.json` and `anim/<name>.png`, in the same device theme,
fonts and screen as the goldens. `--update-goldens` rewrites both; without
it the test checks the measurements against the JSON.

Each JSON lists frames at `t` milliseconds after the trigger (t=0 is the
frame the trigger lands in): every 50 ms to the end, plus every 16 ms through
the first 300 ms. A frame holds `rects` (`[x, y, w, h]` in logical pixels
from the screen's top left, null while that part is not built), `colors`
(`#RRGGBB`, `#RRGGBBAA` while not opaque) and `texts`. The PNG shows the
frames at `stripTimes` left to right, at the phone's density, cropped to the
`crop` regions stacked top to bottom.

| Name | Trigger |
|---|---|
| `typing-dots-8`, `typing-dots-4` | `TypingAnimation` mounts, 2400 ms |
| `typing-row-in`, `typing-row-out` | in `chat-dm`, a sync starts or ends the partner's typing |
| `message-in` | in `chat-dm` while the partner types, one sync brings a reply and ends the typing |
| `message-out` | in `chat-dm-linked`, a tap on send with "On it" typed |
| `switch-network` | in `chat-dm-linked`, a tap on the second network button |
| `composer-type` | in `chat-dm-linked`, "On it" is typed |
| `list-typing-preview` | in `chat-list`, a sync starts typing in a read chat |
| `unread-arrive` | in `chat-list`, a sync brings a message and an unread count of 1 to a read chat |

Syncs go through `Client.handleSync`, the path a real sync takes, so the
timeline, the typing row and the chat list react as they do on the phone.

## Known gaps

- Text whose style names no font family at all falls back to the test
  engine's box font, because Flutter tests cannot change that fallback. The
  one such text on these screens is the homeserver button in the chat list
  search header (`chat_list_header.dart`, `TextStyle(fontSize: 12)`), which
  shows as blocks in `chat-list-search.png` and leaves the query field
  narrower than on the phone.
- Photos in a conversation take the size the app gives them; the fixture's
  `tint` and `outlined` hints about the phone's photo are not reproduced.

## Fonts

Google Sans Flex is loaded from the app's own assets
(`assets/fonts/google_sans_flex`, declared in `pubspec.yaml`) and the icon
font from the Flutter SDK, both through the test asset bundle. `fonts/`
holds Roboto Mono Bold, made from the site's `@fontsource/roboto-mono`
package (OFL 1.1, licence beside it) by `tool/make_fonts.py`, since Flutter
cannot load woff2.
