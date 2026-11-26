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
  spin;

  /// Whether the primitive is a ramp, which a plain pulse cannot stand in
  /// for.
  bool get isRamp => this == quickRise || this == slowRise || this == quickFall;
}

Duration _seconds(double seconds) =>
    Duration(microseconds: (seconds * 1e6).round());

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
      '${at.inMilliseconds}ms, ${scale.toStringAsFixed(2)})';
}

/// How strong a continuous vibration is over time: [points] are moments
/// with a level (0 to 1), and the level glides from each to the next. With
/// [texture] above 0 every other step of the vibration is weakened by that
/// share, which turns a smooth hum into a grainy rumble.
@immutable
class HapticEnvelope {
  final List<(Duration at, double level)> points;
  final double texture;

  const HapticEnvelope(this.points, {this.texture = 0});

  /// An envelope through [points], each a moment in seconds and a level.
  HapticEnvelope.through(
    List<(double seconds, double level)> points, {
    this.texture = 0,
  }) : points = [for (final (at, level) in points) (_seconds(at), level)];

  /// A swell: nothing at [start], [level] at [peak], nothing again at
  /// [end], all in seconds.
  HapticEnvelope.swell(
    double start,
    double peak,
    double end, {
    double level = 0.25,
  }) : this.through([(start, 0), (peak, level), (end, 0)]);

  Duration get end => points.last.$1;

  /// When the envelope is at its strongest.
  Duration get peak => points.reduce((a, b) => b.$2 > a.$2 ? b : a).$1;

  /// The level [ms] in, eased between the points on either side.
  double levelAt(num ms) {
    if (ms <= points.first.$1.inMilliseconds) return points.first.$2;
    for (var i = 1; i < points.length; i++) {
      final (at, level) = points[i];
      if (ms > at.inMilliseconds) continue;
      final (from, fromLevel) = points[i - 1];
      final span = at.inMilliseconds - from.inMilliseconds;
      if (span <= 0) return level;
      final u = (ms - from.inMilliseconds) / span;
      return fromLevel + (level - fromLevel) * (1 - math.cos(u * math.pi)) / 2;
    }
    return points.last.$2;
  }
}

/// What an effect is felt as. A phone that has the primitives plays
/// [beats]. One that can only vary its strength plays [envelope] with the
/// beats that are not ramps as pulses on top. Any other gets plain ticks.
/// With [continuous] set the envelope is the effect and the beats are the
/// stand-in: a phone that can vary its strength plays the envelope even
/// when it has the primitives.
@immutable
class HapticPattern {
  final List<HapticBeat> beats;
  final HapticEnvelope? envelope;
  final bool continuous;

  const HapticPattern(this.beats, {this.envelope, this.continuous = false});

  static const none = HapticPattern([]);

  bool get isEmpty => beats.isEmpty && envelope == null;

  /// One line for each beat and for the envelope, in order of time, to set
  /// beside a recording of the effect.
  String describe() {
    final lines = <(int, String)>[
      for (final beat in beats)
        (
          beat.at.inMilliseconds,
          '${beat.at.inMilliseconds.toString().padLeft(5)} ms  '
              '${beat.endsAt ? 'ends ' : ''}${beat.primitive.name} '
              '${beat.scale.toStringAsFixed(2)}',
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final envelope = this.envelope;
    if (envelope == null) {
      return [for (final (_, line) in lines) line].join('\n');
    }
    final role = continuous
        ? 'played in place of the beats where strength can vary'
        : 'phones without the primitives';
    final texture = envelope.texture > 0 ? ', texture ${envelope.texture}' : '';
    final points = [
      for (final (at, level) in envelope.points)
        '${at.inMilliseconds} ms ${level.toStringAsFixed(2)}',
    ].join(' -> ');
    return [
      for (final (_, line) in lines) line,
      'envelope ($role)$texture: $points',
    ].join('\n');
  }
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

  /// A Pixel 10 Pro's vibrator, as it reports itself.
  static const pixel = HapticCapabilities(
    primitives: {
      HapticPrimitive.thud: Duration(milliseconds: 300),
      HapticPrimitive.click: Duration(milliseconds: 29),
      HapticPrimitive.tick: Duration(milliseconds: 5),
      HapticPrimitive.lowTick: Duration(milliseconds: 12),
      HapticPrimitive.quickRise: Duration(milliseconds: 150),
      HapticPrimitive.slowRise: Duration(milliseconds: 500),
      HapticPrimitive.quickFall: Duration(milliseconds: 100),
      HapticPrimitive.spin: Duration(milliseconds: 133),
    },
    amplitudeControl: true,
  );
}

/// Plays message effects' haptics on Android through the
/// `chat.fluffy.fluffychat/haptics` channel (`EffectHaptics.kt`). It asks
/// the vibrator once what it can do, then turns each pattern into one
/// vibration it can play, so the beats keep time with the animation: a
/// composition of primitives, a waveform whose strength follows the
/// pattern, a run of plain ticks, or a predefined click. The phone's touch
/// feedback setting decides whether anything is felt. Everywhere but
/// Android it does nothing.
class EffectHaptics {
  static const channel = MethodChannel('chat.fluffy.fluffychat/haptics');

  /// The haptics the effects play through. Tests may put a fresh one here.
  static EffectHaptics instance = EffectHaptics();

  Future<HapticCapabilities?>? _capabilities;

  /// Whether this platform has effect haptics at all.
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<HapticCapabilities?> _loadCapabilities() async {
    try {
      final json = await channel.invokeMethod<Map>('capabilities');
      return json == null ? null : HapticCapabilities.fromJson(json);
    } on MissingPluginException {
      // An engine without the native side, such as a test's.
      return null;
    } catch (e, s) {
      Logs().w('Unable to ask what the vibrator can do', e, s);
      return null;
    }
  }

  /// Asks the vibrator what it can do ahead of the first effect, so that
  /// one starts on time.
  void prepare() {
    if (supported) _capabilities ??= _loadCapabilities();
  }

  /// Plays [pattern], from now.
  Future<void> play(HapticPattern pattern) async {
    if (pattern.isEmpty || !supported) return;
    try {
      final capabilities = await (_capabilities ??= _loadCapabilities());
      if (capabilities == null) return;
      final call = plan(pattern, capabilities);
      if (call == null) return;
      await channel.invokeMethod(call.$1, call.$2);
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
  /// [capabilities], or null when there is nothing it can play.
  ///
  /// - `compose`, a list of `[primitive, scale, delayMs]`, when the
  ///   vibrator has every primitive of the pattern;
  /// - `waveform` with `timings` and `amplitudes` when it can vary its
  ///   strength: the envelope, with the beats as pulses over it;
  /// - `predefined` (`click`, `heavyClick` or `tick`) for a lone beat at
  ///   the start, else `waveform` with `timings` only: plain ticks.
  static (String, Object)? plan(
    HapticPattern pattern,
    HapticCapabilities capabilities,
  ) {
    final beats = pattern.beats;
    final envelope = pattern.envelope;
    final durations = capabilities.primitives;
    final composable =
        beats.isNotEmpty &&
        beats.every((beat) => durations.containsKey(beat.primitive));
    final hum = envelope != null && capabilities.amplitudeControl;
    if (composable && !(hum && pattern.continuous)) {
      return ('compose', _composition(beats, durations));
    }
    if (capabilities.amplitudeControl) {
      return ('waveform', _shaped(beats, envelope));
    }
    var ticks = [
      for (final beat in beats)
        if (!beat.primitive.isRamp) beat,
    ];
    if (ticks.isEmpty) {
      // A swell with nothing to tick on: one light tick at its height.
      final at = envelope?.peak ?? (beats.isEmpty ? null : beats.first.at);
      if (at == null) return null;
      ticks = [HapticBeat(HapticPrimitive.tick, at)];
    }
    if (ticks.length == 1 && ticks.single.at == Duration.zero) {
      return (
        'predefined',
        switch (ticks.single.primitive) {
          HapticPrimitive.thud => 'heavyClick',
          HapticPrimitive.tick || HapticPrimitive.lowTick => 'tick',
          _ => 'click',
        },
      );
    }
    return ('waveform', _ticks(ticks));
  }

  /// When [beat] starts, given how long its primitive lasts.
  static int _startOf(HapticBeat beat, int length) => beat.endsAt
      ? math.max(0, beat.at.inMilliseconds - length)
      : beat.at.inMilliseconds;

  /// How late a primitive may start, waiting for the one before it to end,
  /// and still be played.
  static const lateLimit = 50;

  /// [beats] as `[primitive, scale, delayMs]`, each delay counted from the
  /// end of the primitive before it, as `addPrimitive` counts it. The
  /// vibrator plays one primitive at a time, so a beat that would have to
  /// wait more than [lateLimit] milliseconds for the one before it is left
  /// out: it would be felt off its moment.
  static List<List<Object>> _composition(
    List<HapticBeat> beats,
    Map<HapticPrimitive, Duration> durations,
  ) {
    final timed = [
      for (final beat in beats)
        (beat, durations[beat.primitive]!.inMilliseconds),
    ]..sort((a, b) => _startOf(a.$1, a.$2).compareTo(_startOf(b.$1, b.$2)));
    var cursor = 0;
    final composition = <List<Object>>[];
    for (final (beat, length) in timed) {
      final start = _startOf(beat, length);
      if (cursor - start > lateLimit) continue;
      final delay = math.max(0, start - cursor);
      cursor += delay + length;
      composition.add([beat.primitive.name, beat.scale, delay]);
    }
    return composition;
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

  /// How long each step of an envelope holds its strength, in
  /// milliseconds.
  static const step = 20;

  /// The waveform of a vibrator that can vary its strength: [envelope] in
  /// steps of [step] milliseconds, and each beat a pulse over it. With an
  /// envelope the ramps among the beats are left to it.
  static Map<String, Object> _shaped(
    List<HapticBeat> beats,
    HapticEnvelope? envelope,
  ) {
    final pulses = [
      for (final beat in beats)
        if (envelope == null || !beat.primitive.isRamp)
          (beat, _pulseOf(beat.primitive)),
    ];
    var end = envelope?.end.inMilliseconds ?? 0;
    for (final (beat, (length, _)) in pulses) {
      end = math.max(end, _startOf(beat, length) + length);
    }
    // Strength in every 2 ms slot, then runs of equal strength.
    const slot = 2;
    final levels = Uint8List((end / slot).ceil());
    if (envelope != null) {
      for (var i = 0; i < levels.length; i++) {
        final index = i * slot ~/ step;
        var level = envelope.levelAt(index * step + step / 2);
        if (index.isOdd) level *= 1 - envelope.texture;
        levels[i] = (level * 255).round().clamp(0, 255);
      }
    }
    for (final (beat, (length, strength)) in pulses) {
      final start = _startOf(beat, length);
      final level = (strength * beat.scale).round().clamp(1, 255);
      for (
        var i = start ~/ slot;
        i < (start + length) ~/ slot && i < levels.length;
        i++
      ) {
        levels[i] = math.max(levels[i], level);
      }
    }
    final timings = <int>[];
    final amplitudes = <int>[];
    for (var i = 0; i < levels.length; i++) {
      if (amplitudes.isNotEmpty && amplitudes.last == levels[i]) {
        timings.last += slot;
      } else {
        timings.add(slot);
        amplitudes.add(levels[i]);
      }
    }
    return {'timings': timings, 'amplitudes': amplitudes};
  }

  /// How close together two plain ticks can be: a vibrator that cannot
  /// vary its strength turns anything closer into one long buzz.
  static const tickGap = 120;

  /// [beats] as on and off times for a vibrator with one strength, off
  /// first. A beat within [tickGap] milliseconds of the one before it is
  /// left out.
  static Map<String, Object> _ticks(List<HapticBeat> beats) {
    final sorted = [...beats]..sort((a, b) => a.at.compareTo(b.at));
    final timings = <int>[];
    var cursor = 0;
    int? last;
    for (final beat in sorted) {
      final at = beat.at.inMilliseconds;
      if (last != null && at - last < tickGap) continue;
      last = at;
      final length = _pulseOf(beat.primitive).$1;
      timings.addAll([math.max(0, at - cursor), length]);
      cursor = math.max(cursor, at) + length;
    }
    return {'timings': timings};
  }
}
