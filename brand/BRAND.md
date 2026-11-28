# Seam brand

**Seam** is this app's name. Tagline: **Where all your threads meet.** All your chats in one
place, each conversation a thread, sewn together.

Never call Seam an inbox. App and store wording derive from the site copy, `src/copy.ts` in the
seam-site repo.

![Brand preview](preview.png)

## The mark

A round speech bubble made of two pieces of fabric, sewn together and caught mid-stitch:

- **Bubble:** nearly circular, with a normal speech-bubble tail at the lower left.
- **Seam:** a gentle S across the middle, sewn as four stitches. The bubble is a single colour.
- **Stitches:** four running stitches along the seam, cut out of the bubble.
- **Thread:** a free end hangs out and down from the first stitch at the left, where the seam started.
  The working thread runs from the last stitch at the right to the needle.
- **Needle:** sits behind the bubble, its eye out at the top right, separated from the bubble by a
  gap of background colour.

The thread and needle follow how hand sewing really works: the needle is always at the most recent
stitch, and the loose end is where the sewing began.

## Colour

| Name | Hex | Use |
|---|---|---|
| Seam Cobalt | `#1A5AD7` | Icon and launch-screen background; the mark's colour on light backgrounds; the app's default theme colour |
| White | `#FFFFFF` | Bubble, needle and thread; the glyph on dark backgrounds |
| Glyph dark | `#1F1F1F` | The glyph on light backgrounds |

In the app, Seam Cobalt is the default seed of the Material colour scheme (`AppConfig.primaryColor`
and the default of `AppSettings.colorSchemeSeedInt`), and the first colour in Settings > Style.
The system's dynamic colour is an option there, not the default.

Seam Cobalt was chosen to sit apart from other messaging blues (Google Messages `#1A73E8`, Signal
`#3A76F0`, Messenger `#0084FF`, LinkedIn `#0A66C2`).

## Which file for what

| Need | File |
|---|---|
| App icon, any size | `svg/seam-app-icon.svg` (square; launchers and stores apply their own mask) |
| Mark on a dark or cobalt background | `svg/seam-mark.svg` |
| Mark on a white or light background | `svg/seam-mark-on-light.svg` |
| One-colour glyph (status bar, notifications, UI) | `svg/seam-glyph.svg` (`currentColor`), or `-white` / `-dark` |
| Android launcher icon | `android/res/` (adaptive icon: foreground, cobalt background, monochrome layer, plus legacy PNGs) |
| Android notification icon | `android/res/drawable/ic_stat_seam.xml` (a vector drawable written by `source/notification_icon.py`; the status-bar variant of the glyph: bubble, tail and stitches only, with no needle or thread; it fills the 24 dp icon with a 1 dp margin on its longer side) |
| Play Store icon | `store/play-store-icon-512.png` (512 x 512, square, no rounding or shadow) |
| Windows | `windows/app_icon.ico` (exe and taskbar), `tray_icon.ico`, `titlebar_light.ico` and `titlebar_dark.ico` (the bare mark for a light or dark caption; not used by the app, which hides the native title bar) |
| Web | `web/favicon.svg`, `favicon-32.png`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png` |
| Raster sizes | `png/` (app icon square and round, marks, glyphs) |

### Where the app uses it

The app already carries these assets; after changing the mark, rebuild the kit and copy them again:

| In the app | Copied from |
|---|---|
| `android/app/src/main/res/drawable-*/ic_launcher_foreground.png`, `ic_launcher_monochrome.png` | `android/res/mipmap-*/` foreground and monochrome layers (the adaptive icon in `mipmap-anydpi-v26/ic_launcher.xml` points at these, with the background colour in `values/ic_launcher_background.xml`) |
| `android/app/src/main/res/mipmap-*/ic_launcher.png` | `android/res/mipmap-*/ic_launcher.png` (pre-Android 8 launchers) |
| `android/app/src/main/res/drawable/notifications_icon.xml` | `android/res/drawable/ic_stat_seam.xml` (the file keeps its old name because the code loads it by that name) |
| `android/app/src/main/res/drawable-*/splash.png` | `png/seam-mark-1024.png` (white), scaled to 177 dp, centred on Seam Cobalt by `drawable/launch_background.xml` (the launch screen before Android 12) |
| Android 12+ splash screen (`values-v31/styles.xml`, `values-night-v31/styles.xml`) | Seam Cobalt (`values/colors.xml`, `seam_cobalt`) with the launcher foreground `ic_launcher_foreground` as the icon and no icon backing |
| `assets/seam/seam_app_icon.png`, `seam_glyph.png`, `tray_icon.ico` | in-app logo (also the icon in the Windows title bar the app draws), tinted logo and the Windows tray icon |
| `windows/runner/resources/app_icon.ico` | `windows/app_icon.ico` (the exe, taskbar and Alt+Tab) |
| `web/icons/`, `web/favicon.png` | the app icon at the matching sizes |
| Loading animation (`lib/widgets/seam_stitch_loader.dart`) | not copied: the mark is drawn in code from the `source/seam_mark.py` geometry, so a change to the mark has to be made there too. The start screen (`lib/widgets/seam_startup.dart`) draws it white on Seam Cobalt with the icon artboard at 192 dp, centred, which is where the Android 12+ splash screen has the launcher foreground. On a phone the first welcome page (`lib/pages/intro/intro_page.dart`) takes over from it with the mark still (`lib/widgets/seam_mark.dart`) at the same size and place, then shrinks the cobalt to its band; the desktop's empty pane draws it in the glyph's colour at the size of `seam_glyph.png` |

## Rules

- **Clear space:** keep at least a quarter of the mark's width empty around it.
- **Minimum size:** the app icon reads down to 24 px; the glyph down to 16 px. Below 48 px the needle's
  eye and the thread ends simplify, which is expected.
- **Safe zone:** the mark sits inside Android's adaptive-icon safe zone (farthest point 191 of 198 px on
  the 432 px icon), so no launcher shape clips it. Keep it there if the geometry changes.
- **Don't:** recolour the needle or thread, add an outline, a gradient or a shadow, rotate or mirror the
  mark, put the white mark on a white background, add dots or text inside the bubble, or separate the
  needle from the bubble.

## Typography

For a wordmark and headings, use **Plus Jakarta Sans** (SIL Open Font License), carried over from the
original Seam project. Google Sans Flex was also used there; check its licence before shipping it.

## Rebuilding

Everything is generated from one geometry in `source/seam_mark.py`. Change it there, then from this
folder run:

    python3 source/build_brand.py

It needs Python 3 with Pillow, and Google Chrome to rasterise the SVGs. It rewrites `svg/`, `png/`,
`android/`, `store/`, `web/` and `windows/`. Then refresh `preview.png` if the look changed.

## Licence

The Seam name and these assets belong to 312.dev LLC; all rights reserved (see `REUSE.toml`). They are
not covered by the app's AGPL licence.
