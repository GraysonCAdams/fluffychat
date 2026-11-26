// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

/// The kinds of haptic a message effect is felt with. Each is one of
/// Android's composition primitives (`VibrationEffect.Composition`); a phone
/// that cannot play them all gets a plain pulse of a matching strength.
enum HapticPrimitive { thud, click, tick, lowTick, quickRise, slowRise, spin }

/// One haptic in an effect's pattern: [primitive] at [scale] (0 to 1), [at]
/// after the effect starts.
@immutable
class HapticBeat {
  final HapticPrimitive primitive;
  final Duration at;
  final double scale;

  const HapticBeat(this.primitive, this.at, {this.scale = 1});

  /// A beat [seconds] into the effect, the unit the effect scenes keep
  /// their timings in.
  HapticBeat.after(this.primitive, double seconds, {this.scale = 1})
    : at = Duration(microseconds: (seconds * 1e6).round());

  @override
  bool operator ==(Object other) =>
      other is HapticBeat &&
      other.primitive == primitive &&
      other.at == at &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(primitive, at, scale);

  @override
  String toString() =>
      'HapticBeat(${primitive.name}, ${at.inMilliseconds}ms, $scale)';
}

/// Plays message effects' haptics on Android through the
/// `chat.fluffy.fluffychat/haptics` channel (`EffectHaptics.kt`), which
/// sends a whole pattern to the vibrator as one vibration so its beats keep
/// time with the animation. The phone's touch feedback setting decides
/// whether anything is felt. Everywhere but Android it does nothing.
class EffectHaptics {
  static const channel = MethodChannel('chat.fluffy.fluffychat/haptics');

  /// The haptics the effects play through. Tests may put a stand-in here.
  static EffectHaptics instance = EffectHaptics();

  /// Whether this platform has effect haptics at all.
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Plays [beats], one pattern, from now.
  Future<void> play(List<HapticBeat> beats) async {
    if (beats.isEmpty || !supported) return;
    try {
      await channel.invokeMethod('play', [
        for (final beat in beats)
          [beat.primitive.name, beat.at.inMilliseconds, beat.scale],
      ]);
    } on MissingPluginException {
      // An engine without the native side, such as a test's.
    } catch (e, s) {
      Logs().w('Unable to play effect haptics', e, s);
    }
  }

  /// Plays [beats] for an effect shown in [context], unless reduced motion
  /// is on there.
  void playFor(BuildContext context, List<HapticBeat> beats) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    play(beats);
  }
}
