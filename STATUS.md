# feat/effect-haptics status

## What is here
- **Haptics planned in Dart** (`lib/utils/effect_haptics.dart`): an effect's `HapticPattern` is
  beats (composition primitives, optionally ending on a moment) plus an optional `HapticEnvelope`
  (strength over time, with a `texture` for rumble). `EffectHaptics.plan` turns it into one
  channel call for the phone's vibrator, asked once through `capabilities`:
  1. primitives supported: `compose` (a beat that would start more than 50 ms late behind the
     primitive before it is dropped, since primitives play one at a time);
  2. amplitude control: `waveform` with amplitudes (envelope in 20 ms steps, non-ramp beats as
     pulses on top). A pattern marked `continuous` (Gentle) takes this path even on a phone with
     primitives, because a 2 s gradient cannot be built from 500 ms rises;
  3. neither: plain on/off ticks at least 120 ms apart, or a predefined click for a lone beat.
  Desktop and web: nothing. Reduced motion: nothing. Touch feedback off: nothing (Kotlin).
- **Kotlin** (`android/.../EffectHaptics.kt`): `capabilities`, `compose`, `waveform`, `predefined`.
- **One source of truth per effect:** every haptic time is computed from the constants and random
  picks the scene paints with (`screen_effect_scenes.dart`, `EffectBubble.hapticsOf`).
- **Pixel 10 Pro** reports CLICK 29, THUD 300, SPIN 133, QUICK_RISE 150, SLOW_RISE 500,
  QUICK_FALL 100, TICK 5, LOW_TICK 12 ms; `compositionSizeMax` 254 (largest pattern here: about 50).

## Beats (Pixel tier; times from the start of the play)
| Effect | Haptics |
|---|---|
| Slam | thud as the bubble lands (270 ms into the throw) |
| Loud | quick rise ending at 180 ms, thud at 180 ms, tick per shake to the right (11 Hz) until 900 ms |
| Gentle | waveform swell 288 -> peak 1344 (0.45) -> 2400 ms, following the growth |
| Invisible ink | tick on touch down and every 14 px swiped while ink remains |
| Echo | one tick per copy as it comes up (48 over 1150 ms), firmer for larger copies |
| Spotlight | slow rise ending at 700 ms, click as the lamp strikes; quick rise into a click at 3700 ms as the circle opens out |
| Balloons | one tick per balloon as its top crosses the bottom edge (9), a click for the near one; strength by size |
| Confetti | tick/low tick every 70 ms while confetti is in the air (about 0.2 to 4.3 s), strength follows how full the air is |
| Love | thuds at 100, 420, 860, 1180 ms (two heartbeats, each beat pumps the heart up), low tick at 1550 ms as it lets go |
| Lasers | slow rise ending at 800 ms, then 22 pulses 150 ms apart (click on every 4th, tick between), click at 4100 ms |
| Fireworks | low tick as each shell leaves the ground, thud at each burst (500, 1300, 2100, 2900, 3800, 4600 ms) |
| Celebration | click as the sparkler catches (200 ms), a tick per 80 ms step scaled by sparks thrown, until 3.5 s |
| Shooting star | slow rise ending at 1800 ms, click as the star blooms |

## Apple references (measured from recordings; ms from the effect's first frame)
Sources: MacStories iOS 10 review clips (`cdn.macstories.net/002/<name>.mp4`, about 58 fps),
GadgetHacks iOS 11 Echo/Spotlight GIFs and keyword-effect GIFs (Giphy, 15 fps, so about +-67 ms).
- **Spotlight:** dark by 333; disc appears at 733 already centred on the bubble (no sweep), full
  at 800 about 3% oversized, settled by 1067; holds to 3400 breathing about 2%; shrinks about 3%;
  floods out at 3667 to 3800; normal by 4267. Diameter about 0.67 of screen width, edge feather
  5 to 9%, faint cone from the top corner with dust.
- **Echo:** copies come up as specks all over the screen (not out of the bubble): 5 at 133, 16
  at 400, 32 at 667, about 48 at 1150; they grow toward the viewer; a few pass at about 4.9x at
  1870 to 2130; most gone by 2200; over at 2730.
- **Balloons:** 6 to 8, glossy, from the bottom on the sending side drifting to the other; one
  crossing takes 1.6 to 2.1 s; the near one is wider than the screen.
- **Confetti:** sparse to 1200, top third fullest at 1800, bottom at 2400, top clear at 3200,
  gone by about 3800; front falls about 0.6 screen heights a second.
- **Love:** heart pops above the bubble, to 0.7 of its size by 400, lets go about 800, gone by 1600.
- **Lasers:** dark by 167, glow builds to 970, beams from 1000 pulsing every 150 ms, off at
  5300; the bubble stays lit on top; the scene's hue turns once round in about 5.4 s.
- **Loud:** 2.3x by 167, shaking to 700, back by 1130. **Slam:** lands at 267.
- **Gentle:** oversized bubble with small text easing to normal over about 3.8 s.
- **Invisible ink:** specks about 1 pt, about a third change every 50 ms, random walk about 14 pt/s.
- **Shooting star:** fast then slowing arc to 70% across, bloom after the landing.
The scenes are originals in Material terms (theme and bubble colours, emphasized easing) that
follow this choreography; nothing is copied from Apple assets or BlueBubbles code.

## Review material
`flutter test test/screenshots/message_effects_video_test.dart` writes
`build/effects_video/<effect>/f_%04d.png` (60 fps) and `<effect>.haptics.txt` (what a Pixel is
sent, by film time). Encoded copies: `/tmp/effects-v2/<effect>.mp4` and `.haptics.txt`.

## Not done
- **Felt on the device:** nobody has triggered the effects on the phone since the profile build
  was installed, so strengths (Gentle's 0.45 peak, tick scales) are untested by hand.
- Scenes are anchored to the bubble's place when the effect starts; scrolling during an effect
  leaves Spotlight's circle and Lasers' cut-out behind.
- Celebration is still a sparkler; Apple's is gold glitter falling from the top.
