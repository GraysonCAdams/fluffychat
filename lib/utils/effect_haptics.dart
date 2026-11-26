// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

/// The kinds of haptic a message effect is felt with, each one of Android's
/// composition primitives (`VibrationEffect.Composition`).
enum HapticPrimitive {
  thud,
  click,
  tick,
  lowTick,
  quickRise,
  slowRise,
  quickFall,
  spin,
}

/// One haptic in an effect's pattern: [primitive] at [scale] (0 to 1)
/// starting [at] after the effect starts, or, when [endsAt] is set,
/// finishing then, so a rise peaks on the beat whatever its length on the
/// phone.
@immutable
class HapticBeat {
  final HapticPrimitive primitive;
  final Duration at;
  final double scale;
  final bool endsAt;

  const HapticBeat(
    this.primitive,
    this.at, {
    this.scale = 1,
    this.endsAt = false,
  });

  /// A beat [seconds] into the effect, the unit the effect scenes keep
  /// their timings in.
  HapticBeat.after(
    this.primitive,
    double seconds, {
    this.scale = 1,
    this.endsAt = false,
  }) : at = _seconds(seconds);

  @override
  bool operator ==(Object other) =>
      other is HapticBeat &&
      other.primitive == primitive &&
      other.at == at &&
      other.scale == scale &&
      other.endsAt == endsAt;

  @override
  int get hashCode => Object.hash(primitive, at, scale, endsAt);

  @override
  String toString() =>
      'HapticBeat(${primitive.name}, ${endsAt ? 'ends ' : ''}'
      '${at.inMilliseconds}ms, $scale)';
}

Duration _seconds(double seconds) =>
    Duration(microseconds: (seconds * 1e6).round());

/// A swell for phones without the primitives: the vibration grows from
/// nothing at [start] to [amplitude] (of 255) at [peak] and fades back to
/// nothing at [end].
@immutable
class HapticSwell {
  final Duration start, peak, end;
  final int amplitude;

  const HapticSwell(this.start, this.peak, this.end, {this.amplitude = 60});

  HapticSwell.after(
    double start,
    double peak,
    double end, {
    this.amplitude = 60,
  }) : start = _seconds(start),
       peak = _seconds(peak),
       end = _seconds(end);
}

/// What an effect is felt as: [beats] on a phone that has their primitives;
/// on one without, [swell] when it is set, or plain pulses standing in for
/// the beats.
@immutable
class HapticPattern {
  final List<HapticBeat> beats;
  final HapticSwell? swell;

  const HapticPattern(this.beats, {this.swell});

  static const none = HapticPattern([]);

  bool get isEmpty => beats.isEmpty;
}

/// What the phone's vibrator can do, as `EffectHaptics.kt` reports it.
@immutable
class HapticCapabilities {
  /// The primitives the vibrator plays, with how long each lasts.
  final Map<HapticPrimitive, Duration> primitives;

  /// Whether the vibrator can vibrate at a chosen strength.
  final bool amplitudeControl;

  const HapticCapabilities({
    this.primitives = const {},
    this.amplitudeControl = false,
  });

  factory HapticCapabilities.fromJson(Map json) {
    final durations = (json['primitives'] as Map?) ?? const {};
    return HapticCapabilities(
      primitives: {
        for (final primitive in HapticPrimitive.values)
          if (durations[primitive.name] case final num ms)
            primitive: Duration(milliseconds: ms.round()),
      },
      amplitudeControl: json['amplitudeControl'] == true,
    );
  }
}

/// Plays message effects' haptics on Android through the
/// `chat.fluffy.fluffychat/haptics` channel (`EffectHaptics.kt`). It asks
/// the vibrator once what it can do, then turns each pattern into one
/// vibration it can play, so the beats keep time with the animation: a
/// composition of primitives, a swell or a run of pulses, or a predefined
/// click. The phone's touch feedback setting decides whether anything is
/// felt. Everywhere but Android it does nothing.
class EffectHaptics {
  static const channel = MethodChannel('chat.fluffy.fluffychat/haptics');

  /// The haptics the effects play through. Tests may put a fresh one here.
  static EffectHaptics instance = EffectHaptics();

  Future<HapticCapabilities?>? _capabilities;

  /// Whether this platform has effect haptics at all.
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<HapticCapabilities?> _loadCapabilities() async {
    final json = await channel.invokeMethod<Map>('capabilities');
    return json == null ? null : HapticCapabilities.fromJson(json);
  }

  /// Plays [pattern], from now.
  Future<void> play(HapticPattern pattern) async {
    if (pattern.isEmpty || !supported) return;
    try {
      final capabilities = await (_capabilities ??= _loadCapabilities());
      if (capabilities == null) return;
      final (method, arguments) = plan(pattern, capabilities);
      await channel.invokeMethod(method, arguments);
    } on MissingPluginException {
      // An engine without the native side, such as a test's.
    } catch (e, s) {
      Logs().w('Unable to play effect haptics', e, s);
    }
  }

  /// Plays [pattern] for an effect shown in [context], unless reduced
  /// motion is on there.
  void playFor(BuildContext context, HapticPattern pattern) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    play(pattern);
  }

  /// The channel call that plays [pattern] on a vibrator with
  /// [capabilities].
  static (String, Object?) plan(
    HapticPattern pattern,
    HapticCapabilities capabilities,
  ) {
    final beats = pattern.beats;
    final durations = capabilities.primitives;
    if (beats.every((beat) => durations.containsKey(beat.primitive))) {
      return ('compose', _composition(beats, durations));
    }
    final swell = pattern.swell;
    if (swell != null) {
      return capabilities.amplitudeControl
          ? ('waveform', _ramp(swell))
          // One light tick at the height of the swell.
          : (
              'waveform',
              {
                'timings': [swell.peak.inMilliseconds, _pulseOf(HapticPrimitive.tick).$1],
              },
            );
    }
    if (beats.length == 1 && beats.single.at == Duration.zero) {
      return ('predefined', switch (beats.single.primitive) {
        HapticPrimitive.thud => 'heavyClick',
        HapticPrimitive.tick || HapticPrimitive.lowTick => 'tick',
        _ => 'click',
      });
    }
    return ('waveform', _pulses(beats, capabilities.amplitudeControl));
  }

  /// When [beat] starts, given how long its primitive lasts.
  static int _startOf(HapticBeat beat, int length) => beat.endsAt
      ? math.max(0, beat.at.inMilliseconds - length)
      : beat.at.inMilliseconds;

  /// [beats] as `[primitive, scale, delayMs]`, each delay counted from the
  /// end of the primitive before it, as `addPrimitive` counts it.
  static List<List<Object>> _composition(
    List<HapticBeat> beats,
    Map<HapticPrimitive, Duration> durations,
  ) {
    final timed = [
      for (final beat in beats)
        (beat, durations[beat.primitive]!.inMilliseconds),
    ]..sort((a, b) => _startOf(a.$1, a.$2).compareTo(_startOf(b.$1, b.$2)));
    var cursor = 0;
    return [
      for (final (beat, length) in timed)
        () {
          final delay = math.max(0, _startOf(beat, length) - cursor);
          cursor += delay + length;
          return <Object>[beat.primitive.name, beat.scale, delay];
        }(),
    ];
  }

  /// How long a pulse standing in for [primitive] lasts, and how strong it
  /// is at full scale (of 255).
  static (int, int) _pulseOf(HapticPrimitive primitive) => switch (primitive) {
    HapticPrimitive.thud => (40, 255),
    HapticPrimitive.click => (20, 200),
    HapticPrimitive.quickRise => (50, 170),
    HapticPrimitive.slowRise => (90, 130),
    HapticPrimitive.quickFall => (40, 120),
    HapticPrimitive.spin => (40, 150),
    HapticPrimitive.lowTick => (14, 90),
    HapticPrimitive.tick => (10, 110),
  };

  /// [beats] as pulses, gaps between them off; strengths only when the
  /// vibrator can vary them.
  static Map<String, Object> _pulses(
    List<HapticBeat> beats,
    bool amplitudeControl,
  ) {
    final timed = [
      for (final beat in beats) (beat, _pulseOf(beat.primitive)),
    ]..sort((a, b) => _startOf(a.$1, a.$2.$1).compareTo(_startOf(b.$1, b.$2.$1)));
    final timings = <int>[];
    final amplitudes = <int>[];
    var cursor = 0;
    for (final (beat, (length, strength)) in timed) {
      final gap = math.max(0, _startOf(beat, length) - cursor);
      timings.addAll([gap, length]);
      amplitudes.addAll([0, (strength * beat.scale).round().clamp(1, 255)]);
      cursor += gap + length;
    }
    return {'timings': timings, if (amplitudeControl) 'amplitudes': amplitudes};
  }

  /// How long each step of a swell holds its strength.
  static const rampStep = 20;

  /// [swell] as steps of [rampStep] milliseconds whose strength follows a
  /// sine up to the peak and back down.
  static Map<String, Object> _ramp(HapticSwell swell) {
    final start = swell.start.inMilliseconds;
    final peak = swell.peak.inMilliseconds;
    final end = swell.end.inMilliseconds;
    final timings = <int>[start];
    final amplitudes = <int>[0];
    for (var t = start; t < end; t += rampStep) {
      final step = math.min(rampStep, end - t);
      final middle = t + step / 2;
      final level = middle < peak
          ? math.sin((middle - start) / (peak - start) * math.pi / 2)
          : math.cos((middle - peak) / (end - peak) * math.pi / 2);
      timings.add(step);
      amplitudes.add((swell.amplitude * level).round().clamp(0, 255));
    }
    return {'timings': timings, 'amplitudes': amplitudes};
  }
}
