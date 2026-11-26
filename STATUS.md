# feat/effect-haptics status

## Done (e6b5c4f3a, on fork)
- Haptics for every message effect on Android: `lib/utils/effect_haptics.dart` (Dart service,
  channel `chat.fluffy.fluffychat/haptics`, no-op off Android, gated on reduced motion) and
  `android/.../EffectHaptics.kt` (one `VibrationEffect.Composition` when all primitives are
  supported, else predefined click/tick for a lone beat, else a waveform of pulses; `USAGE_TOUCH`;
  skipped when `HAPTIC_FEEDBACK_ENABLED` is 0). Registered in `MainActivity.provideEngine`.
- Beat times live beside the animation timings: screen effects in each scene's `haptics`
  (`screen_effect_scenes.dart`, fired by `ScreenEffectHost.play`), Loud and Gentle in
  `EffectBubble.hapticsOf`, ink swipe ticks in `InvisibleInk._tickAt`.
- Tests: `haptics` group in `test/widgets/message_effects_test.dart` (fake channel). Analyze clean,
  `flutter test test/pages test/widgets test/utils` green (709 passed, 2 skipped). Each new test was
  shown to fail under a perturbation.
- Pixel 10 Pro (API 37) reports every primitive used, with THUD 300 ms, SLOW_RISE 500 ms,
  QUICK_RISE 150 ms, QUICK_FALL 100 ms, TICK 5 ms, LOW_TICK 12 ms, CLICK 29 ms.
  The profile APK of e6b5c4f3a is installed.

## Not done
- **Device check:** the phone stayed locked, so no effect was triggered and `dumpsys
  vibrator_manager` shows none of this app's vibrations yet.
- **Gentle as a swell (Grayson: "gentle is supposed to do a gradient vibration"):** Gentle is still
  one soft tick at 288 ms. Started on branch `wip/effect-haptics-swell` (34effebde, pushed; does
  not build). It moves planning into Dart so fallbacks are testable: `capabilities` call (primitive
  durations, amplitude control), `HapticPattern` with an optional `HapticSwell` (sine ramp up to
  ~60/255 and back, 20 ms steps, for vibrators with amplitude control; one light tick at the peak
  without it), `HapticBeat.endsAt` so a rise peaks on its beat. Scenes there already give
  Spotlight and Shooting Star a slow rise into their landing plus a swell. Still to do there:
  - `EffectBubble.hapticsOf` returning `HapticPattern`: Gentle = slowRise 0.2 at 288 ms, slowRise
    0.35 ending at 1344 ms (fastest growth), quickFall 0.25 at 1344 ms, lowTick 0.2 at 2400 ms,
    swell 288/1344/2400; Loud's quick rise ending at 304 ms instead of starting at 0.
  - `InvisibleInk._tickAt` wrapping its beat in `HapticPattern`.
  - `EffectHaptics.kt`: replace `play` with `capabilities`, `compose` (`[name, scale, delayMs]`),
    `waveform` (`timings`, optional `amplitudes`) and `predefined` (`click`, `heavyClick`, `tick`),
    and map the new `quickFall` primitive.
  - Tests: answer `capabilities` in the fake channel (reset `EffectHaptics.instance` per test);
    Gentle with primitives, with amplitude control only (ramp), with neither (one tick), each
    proven to fail first.
- **Invisible ink look (sharp, dense, twinkling specks, text fully hidden, no per-frame mask
  image):** not started.
