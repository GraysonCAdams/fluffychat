# Dev control

A small HTTP server inside the app that lets a script drive Seam and read
its rendering: tap a widget by key or semantics label, type, press keys,
scroll, open a route or room, take a screenshot of what Flutter drew, and
read the engine's own per-frame build and raster times. It works on a
covered or background window: input is fed to Flutter's gesture and
keyboard pipeline, so the real mouse does not move and nothing takes focus.

It exists only in builds made with `--dart-define=SEAM_DEV_CONTROL=true`.

## Why this and not the alternatives

| Option | Verdict |
|---|---|
| Playwright | Drives browsers only; it cannot see a native Flutter window. |
| Flutter web build + Playwright | Not used. The web build is a different app for this purpose: no Win32 chrome, chat windows, FFI spell check or Windows clipboard, a CanvasKit/Skwasm renderer instead of the Windows engine, so its frame times say nothing about the Windows app. Seam's web build is also untested (`lib/utils/logcat_mirror.dart` imports `dart:ffi` unconditionally), and it would need its own login. |
| `flutter_driver` extension | Needs the VM service, so not in release builds, and its URI changes every launch; the extension is aimed at a test harness that launched the app. No frame summaries without a trace. |
| VM service + `flutter attach` / DevTools | Good for one-off profiling in a profile build, but needs the app launched by `flutter run` or the service URI from its stdout, and DevTools is a UI, not a script. |
| `integration_test`, Patrol | Run a test that launched the app; they cannot attach to the running app with Grayson's account. |
| marionette / flutter MCP-style servers | VM-service extensions: same debug/profile-only, URI-discovery limits as `flutter_driver`. |

An in-app server behind a compile-time flag has none of those limits: it runs
in profile builds (the ones whose frame times mean something), it is
reachable at a fixed port with a token from a file, and the same code serves
Windows and Android.

## Building with it

```sh
# Windows, profile (real frame times; release works too)
flutter build windows --profile --dart-define=SEAM_DEV_CONTROL=true

# Android, profile (installs as chat.fluffy.fluffychat.fork, see Android below)
flutter build apk --profile --dart-define=SEAM_DEV_CONTROL=true
```

`--dart-define=SEAM_DEV_CONTROL_PORT=<port>` changes the port it tries first
(47913). If the port is taken it takes any free one; the token file says
which.

Every other build leaves the server out. `kDevControlEnabled`
(`lib/utils/dev_control/dev_control_flag.dart`) is a compile-time constant,
so the one call that starts the server (`startGui` in `lib/main.dart`) is dead
code and the AOT compiler drops the server. `test/utils/dev_control_test.dart`
checks the flag is off by default, and
`tools/devctl/check_stripped.sh` checks a built binary:

```sh
tools/devctl/check_stripped.sh build/windows/x64/runner/Release/data/app.so            # must say "stripped"
tools/devctl/check_stripped.sh build/windows/x64/runner/Profile/data/app.so --expect-present  # flag build
tools/devctl/check_stripped.sh build/app/outputs/flutter-apk/app-release.apk
```

## Running it in place of the installed Seam (Windows)

Only one Seam may run: the runner holds the `Local\dev.threeonetwo.seam`
mutex and a second launch only brings the first window forward. A dev
control build is the same app with the same data folder
(`%APPDATA%\threeonetwo\Seam`), so it is swapped in, never run beside it:

1. Quit Seam from its tray menu (closing the window only hides it). Check it
   is gone: `tasklist /fi "imagename eq seam.exe"` shows nothing.
2. Start the flag build: `build\windows\x64\runner\Profile\seam.exe`. It takes
   the lock and opens the normal database, logged in as usual.
3. When done, quit it from the tray and start the installed Seam again.

Never run two at once against the same data, whatever the build.

## Connecting

On start the app writes `devctl.json`:

| Platform | Where |
|---|---|
| Windows | `%LOCALAPPDATA%\Seam\devctl.json` (from WSL `/mnt/c/Users/<you>/AppData/Local/Seam/devctl.json`) |
| Android | `/sdcard/Android/data/<package>/files/devctl.json`, readable with `adb shell cat` |
| Others | the app support folder |

```json
{ "url": "http://127.0.0.1:47913", "port": 47913, "token": "<64 hex>", "pid": 1234, "platform": "windows", "startedAt": "..." }
```

The token is new on every start. Every request sends
`Authorization: Bearer <token>`; without it the answer is 401. A request
with an `Origin` header (a web page) is refused with 403. The server listens
on 127.0.0.1 only.

### From WSL

This machine's WSL uses NAT networking (`networkingMode=mirrored` is
commented out in `C:\Users\gray\.wslconfig`). In NAT mode a Windows server on
127.0.0.1 is not reachable from WSL, neither as `localhost` nor at the host
IP (checked 2026-11-27: both refused, while `curl.exe` from WSL connected).
So from WSL the client sends each request through Windows' `curl.exe`; it
picks that by itself when a direct connection fails. With mirrored
networking `localhost` would work directly.

```sh
D=/mnt/c/src/fluffychat-devctl/tools/devctl/devctl.py   # or the main checkout
python3 $D info
```

### Android

Debug and profile APKs install as `chat.fluffy.fluffychat.fork`
(`android/app/build.gradle.kts`), a separate app beside the installed Seam
with its own data, so it needs its own login. Only a release build with the
flag, signed with the release key, replaces the installed app and keeps its
data; release frame times are as real as profile ones, but a release build
has no VM service for DevTools.

```sh
python3 tools/devctl/devctl.py --android info       # reads the token over adb, runs adb forward
python3 tools/devctl/devctl.py --android --serial <id> tap --text "Chats"
```

The client runs `adb forward tcp:<port> tcp:<port>` itself.

## The client

`tools/devctl/devctl.py` (Python 3, standard library only) sends one request
per command and prints the JSON answer; the exit code is 1 when the answer is
not 200. `devctl.py <command> --help` lists every flag.

Targets, on every command that takes one:

| Flag | Request field | Matches |
|---|---|---|
| `--key K` | `key` | a widget whose `ValueKey`/`ObjectKey` value prints as `K` |
| `--text T` / `--contains T` | `text` / `textContains` | a `Text`, `RichText` or `EditableText` by exact text / substring |
| `--type T` | `type` | a widget class name, e.g. `TextField` |
| `--label L` / `--label-contains T` | `label` / `labelContains` | a semantics node's label exactly / text in its label, value, hint or tooltip |
| `--tooltip T` | `tooltip` | a semantics tooltip (every `IconButton` with a tooltip) |
| `--id I` | `identifier` | a semantics identifier (`Semantics(identifier: ...)`) |
| `--x X --y Y` | `x`, `y` | a point in logical pixels of the view |
| `--index N` | `index` | the Nth match (default 0) |
| `--view V` | `view` | a Flutter view id (chat windows are views of their own) |

Widget matches that a press at their centre would actually reach come first
(`hittable` in the answer). Widget finders walk the element tree and cost
nothing per frame. Semantics finders turn the semantics tree on, which adds
build time to every frame while it is on; it turns itself off 60 s after
the last semantics request, or at once with `sem-release`. Frame summaries
report `semantics: true` when it was on.

## Requests

All answers are JSON with `"ok": true`, except `/screenshot` (PNG). Errors
come as `{"error": "..."}` with 400 (bad request), 404 (no such request, no
match, nothing focused) or 500. POST bodies are JSON objects; GET takes query
parameters. Each heading gives the client command.

### `GET /info`: `devctl.py info`
pid, platform, build mode, current route, display refresh rate, views (id,
logical size, pixel ratio), whether semantics is on, frames recorded and the
clock skew between marks and frame times.

### `GET /widgets`: `devctl.py widgets --contains "Item"`
Matches in the element tree, each with `description`, `rect` (`x`, `y`, `w`,
`h`), `center`, `view`, `hittable`. `limit` (default 50).

### `GET /semantics`: `devctl.py sem --label-contains Emoji`
Semantics nodes, each with `id`, `label`, `value`, `hint`, `tooltip`,
`identifier`, `role`, `flags`, `actions`, `rect`. With no filter, every node
that says something or takes an action. `limit` (default 500).
`POST /semantics/release` (`devctl.py sem-release`) turns semantics off.

### `POST /tap`: `devctl.py tap --tooltip "Send"`
Press and release at the target's centre. `kind`: `mouse` (default on
desktop) or `touch` (default on Android); `count: 2` for a double tap;
`holdMs` (default 40). Returns the target it pressed.

### `POST /longpress`: `devctl.py longpress --contains "hello"`
Holds for 700 ms (`holdMs` to change).

### `POST /rightclick`: `devctl.py rightclick --contains "hello"`
Secondary-button mouse click, which opens context menus on desktop.

### `POST /hover`: `devctl.py hover --tooltip "Emoji"`
Moves the injected mouse over the target and leaves it there (tooltips,
hover states). `devctl.py hover --leave` takes it off the app. Every other
pointer request takes the injected mouse off when it ends.

### `POST /scroll`: `devctl.py scroll --type ListView --dy 600 --steps 10`
Mouse-wheel scroll of `dx`/`dy` logical pixels over the target (positive
`dy` scrolls down), split into `steps` events `intervalMs` (16) apart.

### `POST /drag`: `devctl.py drag --key list --dy -400 --ms 300`
Press at the target, move by `dx`/`dy` over `durationMs` (300) in 16 ms
steps, release. Touch by default, which is how lists fling.

### `POST /type`: `devctl.py type "hello" --into --tooltip "Message" --submit`
Types `value` into the focused text field at its cursor, the way an input
method commits text (`onChanged` fires). With a target (`--into` plus target
flags) it taps the target first to focus it. `replace: true` replaces the
whole text; `submit: true` then sends the field's input action. 404 when no
field has focus. Returns the field's text.

### `POST /key`: `devctl.py key ctrl+k` / `devctl.py key down down enter`
`keys` is a chord or a list of chords: modifiers (`ctrl`, `shift`, `alt`,
`meta`/`win`) joined with `+` to a key (`a`-`z`, `0`-`9`, `f1`-`f12`,
`enter`, `escape`, `tab`, `space`, `backspace`, `delete`, `up`, `down`,
`left`, `right`, `home`, `end`, `pageup`, `pagedown`). They go through
`HardwareKeyboard` and the focus system, so `Shortcuts`, `CallbackShortcuts`
and `Focus.onKeyEvent` see them. Text fields take typed text from the input
method, not from key events: use `/type` for text. Returns whether the app
handled each chord.

### `POST /go`: `devctl.py go /rooms/settings` / `devctl.py room '!abc:example.org'`
Opens `location` in the main router, or `roomId` as `/rooms/<id>`.
`GET /route` (`devctl.py route`) returns the current location.

### `POST /wait`: `devctl.py wait --text "Sent" --timeout-ms 8000`
Polls every 100 ms until the target exists (or, with `gone: true`, until it
does not); 404 on timeout (`timeoutMs`, default 5000).

### `GET /screenshot`: `devctl.py shot /tmp/seam.png [--key composer] [--scale 0.5]`
A PNG of the view's root layer as Flutter composited it, at physical pixels
times `scale`. With a target, only the target's rect. It is Flutter's own
rendering, so it works with the window covered, but it does not include
native windows (file pickers, system menus) or anything Windows draws.

### `POST /frames/mark`, `GET /frames`: frame timings
The server records the engine's `FrameTiming` for every frame
(`SchedulerBinding.addTimingsCallback`).

```sh
python3 $D mark emoji
python3 $D tap --tooltip "Emoji"
python3 $D frames --since emoji        # waits 1.1 s for the engine's next batch
# or all in one, recording 1.5 s after the tap:
python3 $D measure emoji --settle-ms 1500 -- tap --tooltip "Emoji"
```

`GET /frames` takes `since` and `until` (mark names; all kept frames without
them), `wait` (ms, default 1100: the engine hands timings over about once a
second in profile and release builds, so a summary read at once misses the
last frames) and `detail=1` (every frame). It answers:

| Field | Meaning |
|---|---|
| `frames`, `spanMs`, `fps` | frames in the span, first vsync to last raster end, frames per second over that |
| `refreshRate`, `budgetMs` | the display's rate and one vsync at it |
| `overBudget`, `over16ms`, `over8ms` | frames whose build or raster took longer than the budget / 16.7 ms / 8.3 ms |
| `buildOverBudget`, `rasterOverBudget` | which thread went over |
| `buildMs`, `rasterMs`, `totalMs` | `avg`, `p50`, `p90`, `p99`, `max`; total is vsync to raster end |
| `missedVsyncs`, `longestGapMs` | vsyncs with no frame between consecutive frames, and the longest gap |
| `worst` | the five slowest frames |
| `mode`, `semantics` | build mode, and whether semantics was on (it costs build time) |

Flutter draws nothing while nothing changes, so `fps` and `missedVsyncs`
only mean dropped frames across a span that animates throughout (opening a
picker, scrolling). Measure in a profile or release build; debug frame times
are several times slower. The client's own requests run on the UI thread
too, so poll sparingly during a measurement (`measure` sends none while it
records). `POST /frames/clear` drops recorded frames and marks.

### `GET /logs`: `devctl.py logs --lines 50 --level warning`
The app's last log lines (`Logs()`), each with `seq`, `time`, `level`,
`text`, scrubbed of tokens the same way as logcat. `since=<seq>` returns only
newer lines. Keeps the last 2000.

### Anything else
`devctl.py raw POST /tap '{"key":"x","kind":"touch"}'` sends a request as
written (GET turns the JSON into query parameters).

## Tests

- `test/utils/dev_control_test.dart`: every request against
  `test/utils/dev_control_fixture.dart` in widget tests, frame summaries, the
  token file, the token and `Origin` checks, and that the server listens on
  loopback only.
- `integration_test/dev_control_test.dart`: the same over real HTTP on the
  real engine, with a GPU screenshot and real frame timings. It pumps its own
  app and never opens Seam's data, so it may run beside an installed Seam:
  debug builds of the runner skip the single-instance lock when
  `SEAM_SKIP_INSTANCE_LOCK` is set (`windows/runner/main.cpp`; profile and
  release builds always take it). The test window is created hidden and
  stays hidden.

  ```bat
  set SEAM_SKIP_INSTANCE_LOCK=1
  flutter test integration_test/dev_control_test.dart -d windows
  ```

## Code

| File | Holds |
|---|---|
| `lib/utils/dev_control/dev_control_flag.dart` | the compile-time flag and port |
| `lib/utils/dev_control/dev_control.dart` | request handling, the HTTP server, the token file, the log tail |
| `lib/utils/dev_control/finder.dart` | element-tree and semantics finders |
| `lib/utils/dev_control/input_injector.dart` | pointer, key and text injection |
| `lib/utils/dev_control/frame_recorder.dart` | frame timings and summaries |
| `tools/devctl/devctl.py` | the client |
| `tools/devctl/check_stripped.sh` | checks a built binary for the server |
