// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/effect_haptics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pixel = HapticCapabilities.pixel;
  const amplitudeOnly = HapticCapabilities(amplitudeControl: true);
  const plain = HapticCapabilities();

  HapticBeat beat(HapticPrimitive primitive, int ms, {bool endsAt = false}) =>
      HapticBeat(primitive, Duration(milliseconds: ms), endsAt: endsAt);

  /// Expects [pattern] to be played on [vibrator] by calling [method] with
  /// [arguments].
  void expectPlan(
    HapticPattern pattern,
    HapticCapabilities vibrator,
    String method,
    Object arguments,
  ) {
    final (planned, with_) = EffectHaptics.plan(pattern, vibrator)!;
    expect(planned, method);
    expect(with_, arguments);
  }

  group('a vibrator with the primitives', () {
    test('counts each delay from the end of the primitive before', () {
      final pattern = HapticPattern([
        beat(HapticPrimitive.tick, 100),
        // A thud lasts 300 ms.
        beat(HapticPrimitive.thud, 200),
        beat(HapticPrimitive.click, 900),
      ]);
      expectPlan(pattern, pixel, 'compose', [
        ['tick', 1.0, 100],
        ['thud', 1.0, 95],
        ['click', 1.0, 400],
      ]);
    });

    test('starts a rise early so that it ends on its beat', () {
      // A slow rise lasts 500 ms, a quick one 150 ms.
      final pattern = HapticPattern([
        beat(HapticPrimitive.slowRise, 1150, endsAt: true),
        beat(HapticPrimitive.click, 1150),
        beat(HapticPrimitive.quickRise, 2000, endsAt: true),
      ]);
      expectPlan(pattern, pixel, 'compose', [
        ['slowRise', 1.0, 650],
        ['click', 1.0, 0],
        ['quickRise', 1.0, 671],
      ]);
    });

    test('leaves out a beat that would be felt late', () {
      final pattern = HapticPattern([
        beat(HapticPrimitive.thud, 0),
        // Inside the thud: it could not start before 300 ms.
        beat(HapticPrimitive.tick, 100),
        // Near enough the thud's end to wait for it.
        beat(HapticPrimitive.lowTick, 260),
        beat(HapticPrimitive.tick, 500),
      ]);
      expectPlan(pattern, pixel, 'compose', [
        ['thud', 1.0, 0],
        ['lowTick', 1.0, 0],
        ['tick', 1.0, 188],
      ]);
    });
  });

  group('a vibrator that can only vary its strength', () {
    test('plays the envelope with the beats as pulses over it', () {
      final pattern = HapticPattern([
        beat(HapticPrimitive.slowRise, 400, endsAt: true),
        beat(HapticPrimitive.click, 400),
      ], envelope: HapticEnvelope.swell(0, 0.4, 0.6, level: 0.2));
      final (method, arguments) = EffectHaptics.plan(pattern, amplitudeOnly)!;
      expect(method, 'waveform');
      final waveform = arguments as Map<String, Object>;
      final timings = waveform['timings']! as List<int>;
      final amplitudes = waveform['amplitudes']! as List<int>;
      expect(timings.length, amplitudes.length);
      expect(timings.reduce((a, b) => a + b), 600);
      int at(int ms) {
        var cursor = 0;
        for (var i = 0; i < timings.length; i++) {
          cursor += timings[i];
          if (ms < cursor) return amplitudes[i];
        }
        return 0;
      }

      // Rising to a fifth of full strength, the click (200 of 255 for
      // 20 ms) on top at 400 ms, then fading.
      expect(at(100), inExclusiveRange(0, at(300)));
      expect(at(390), closeTo(0.2 * 255, 2));
      expect(at(410), 200);
      expect(at(430), inExclusiveRange(20, 51));
      expect(at(590), lessThan(5));
    });

    test('plays ramps as pulses when there is no envelope', () {
      final pattern = HapticPattern([
        beat(HapticPrimitive.quickRise, 0),
        beat(HapticPrimitive.thud, 300),
      ]);
      expectPlan(pattern, amplitudeOnly, 'waveform', {
        'timings': [50, 250, 40],
        'amplitudes': [170, 0, 255],
      });
    });

    test('keeps the primitives when the envelope is only a stand-in', () {
      final pattern = HapticPattern([
        beat(HapticPrimitive.click, 100),
      ], envelope: HapticEnvelope.swell(0, 0.1, 0.2));
      expect(EffectHaptics.plan(pattern, pixel)!.$1, 'compose');
      expect(
        EffectHaptics.plan(
          HapticPattern(
            pattern.beats,
            envelope: pattern.envelope,
            continuous: true,
          ),
          pixel,
        )!.$1,
        'waveform',
      );
    });
  });

  group('a plain vibrator', () {
    test('plays a lone beat at the start as a predefined effect', () {
      expect(
        EffectHaptics.plan(
          HapticPattern([beat(HapticPrimitive.thud, 0)]),
          plain,
        ),
        ('predefined', 'heavyClick'),
      );
      expect(
        EffectHaptics.plan(
          HapticPattern([beat(HapticPrimitive.tick, 0)]),
          plain,
        ),
        ('predefined', 'tick'),
      );
    });

    test('ticks on the beats, off first, and skips ramps', () {
      final pattern = HapticPattern([
        beat(HapticPrimitive.slowRise, 500, endsAt: true),
        beat(HapticPrimitive.click, 500),
        beat(HapticPrimitive.thud, 1000),
      ]);
      expectPlan(pattern, plain, 'waveform', {
        'timings': [500, 20, 480, 40],
      });
    });

    test('thins ticks that would run into one buzz', () {
      final pattern = HapticPattern([
        for (var ms = 0; ms < 600; ms += 60) beat(HapticPrimitive.tick, ms),
      ]);
      // One every 120 ms is left of one every 60.
      expectPlan(pattern, plain, 'waveform', {
        'timings': [0, 10, 110, 10, 110, 10, 110, 10, 110, 10],
      });
    });
  });

  test('nothing is planned for an empty pattern', () {
    expect(HapticPattern.none.isEmpty, isTrue);
    expect(EffectHaptics.plan(HapticPattern.none, plain), isNull);
  });
}
