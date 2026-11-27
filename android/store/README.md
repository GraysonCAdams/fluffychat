# Play store listing

The words and pictures on Seam's Google Play page, under version control. `copy/` is the source:
nothing else in this repo holds a sentence that appears on the store page. Seam is listed on Play
only, so every file here feeds Play.

`STORE-LAUNCH.md` is the ordered list of what a person still has to do to publish.

| File | Play Console field | Cap |
|---|---|---|
| `copy/name.txt` | App name | 30 |
| `copy/play-short-description.txt` | Short description | 80 |
| `copy/description.txt` | Full description | 4000 |
| `copy/release-notes.txt` | Release notes (What's new) | 500 |
| `copy/play-app-access-instructions.txt` | App content, App access instructions | none published |
| `copy/play-alt-text.txt` | Alt text, one line per graphic: the feature graphic, then each phone screenshot in order | 140 a line |
| `declarations/play-tags.txt` | Store settings, Tags, one per line | 5 tags |
| `icon-512.png` | App icon (512x512, 32-bit PNG) | |
| `play/feature-graphic.png` | Feature graphic (1024x500, 24-bit PNG, no alpha) | |
| `play/screenshots/` | Phone screenshots (see its README) | 2 to 8 |

## The rules the copy keeps

`node android/store/check.js` (from the repo root) enforces them and exits 1 on any problem:

- every field within its cap, counted in Unicode characters;
- no em or en dash, smart quote or tab;
- none of the price and ranking words Play's metadata policy bars (`free`, `best`, `top`, `new`,
  `#1`);
- no other company's product in the name, short description or release notes. Messaging
  networks appear only in the full description, as examples of bridges the user runs, beside a
  sentence saying Seam is not affiliated with them and includes no bridges;
- never iMessage, Apple or Google Messages (the legal review's top risk), and never a named
  homeserver or bridge as a recommendation;
- the full description keeps the link to the source code, which AGPL section 6 requires next to
  the binary;
- one alt-text line per graphic, and the review account's details as placeholders only.

Seam is a modified FluffyChat, and the full description says so with the original authors'
names. That credit is required by the licence and is fine in the description; the name FluffyChat
never goes in the title, the icon or a graphic.

## Fields with no file

| Field | Value |
|---|---|
| App category | Communication |
| Contact email | `graysonadams@gmail.com` (the address the privacy policy gives) |
| Website | `https://seam.312.dev` |
| Privacy policy | `https://seam.312.dev/privacy` |
| Account deletion URL | a page on seam.312.dev that explains deletion (STORE-LAUNCH.md, step 6) |

Data safety, content rating, target audience, permission and foreground-service declarations are
answered in the seam-site repository, `content/legal/play-declarations.md`, row by row and cited
to the code. They are typed into the console, not stored here.

## Graphics

    python3 android/store/make-graphics.py        # from the repo root

writes `icon-512.png` from `brand/store/play-store-icon-512.png` (adding the alpha channel Play
asks for) and draws `play/feature-graphic.png`: the mark, the name and the tagline on Seam
Cobalt, rendered by headless Chrome in Plus Jakarta Sans. It needs Pillow, Google Chrome and a
network connection for the font. Re-run it whenever `brand/` is rebuilt.

The phone screenshots come from the HTML recreations in the seam-site repository; see
`play/screenshots/README.md`.

## Upstream's fastlane listing

`android/fastlane/metadata/` held FluffyChat's own listing text, logo and screenshots and has been
removed. `android/fastlane/Appfile` names the release package `dev.threeonetwo.seam`, so the
Fastfile's upload lanes would push an AAB to Seam's app, not upstream's; they skip metadata and
are not needed for a first release by hand.
