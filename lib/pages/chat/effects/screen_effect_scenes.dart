// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The full screen effects, each a scene that paints itself for a moment in
/// time. A scene picks everything random about itself when it is made, so
/// painting the same moment twice gives the same picture.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluffychat/utils/effect_haptics.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:material_ui/material_ui.dart';

/// The colours a scene paints with: the bubble's own, and the theme's
/// accents around it.
class EffectPalette {
  /// The colour of the bubble that carries the effect.
  final Color bubble;
  final Color onBubble;

  /// The theme's accents, the bubble colour first.
  final List<Color> accents;

  /// Party colours for balloons and confetti: the bubble's hue and seven
  /// more spaced round the colour wheel, all vivid, ordered so neighbours
  /// in the list are far apart on the wheel.
  final List<Color> festive;

  /// What a dimmed conversation is dimmed with.
  final Color scrim;

  /// The red of hearts: the theme's error hue at full strength.
  final Color love;

  /// The colour of light: sparks, stars and beams fade towards it.
  final Color glow;

  /// Whether the conversation is dark already, so that light has to be
  /// painted onto it to show.
  final bool dark;

  const EffectPalette({
    required this.bubble,
    required this.onBubble,
    required this.accents,
    required this.festive,
    required this.scrim,
    required this.love,
    required this.glow,
    this.dark = false,
  });

  factory EffectPalette.of(ThemeData theme, {Color? bubble, Color? onBubble}) {
    final scheme = theme.colorScheme;
    final base = bubble ?? scheme.primary;
    final hsl = HSLColor.fromColor(base);
    // The theme's accents can sit close to one another, so two turns of
    // the bubble's hue join them to keep confetti and balloons varied.
    Color turned(double degrees) => hsl
        .withHue((hsl.hue + degrees) % 360)
        .withSaturation(math.max(hsl.saturation, 0.6))
        .withLightness(hsl.lightness.clamp(0.45, 0.65))
        .toColor();
    final dark = theme.brightness == Brightness.dark;
    Color party(int step) {
      final hue = (hsl.hue + step * 45) % 360;
      // Blues read dark and yellows light at the same lightness, so the
      // lightness leans against that.
      final lightness = 0.55 + 0.07 * math.cos((hue - 250) * math.pi / 180);
      return HSLColor.fromAHSL(1, hue, 0.88, lightness).toColor();
    }

    return EffectPalette(
      bubble: base,
      onBubble: onBubble ?? scheme.onPrimary,
      accents: [
        base,
        scheme.primary,
        scheme.tertiary,
        scheme.secondary,
        dark ? scheme.primaryContainer : scheme.inversePrimary,
        scheme.tertiaryContainer,
        turned(140),
        turned(-110),
      ],
      festive: [
        for (final step in const [0, 3, 6, 1, 4, 7, 2, 5]) party(step),
      ],
      scrim: Color.lerp(const Color(0xFF000000), scheme.primary, 0.08)!,
      love: HSLColor.fromAHSL(
        1,
        HSLColor.fromColor(scheme.error).hue,
        0.92,
        0.52,
      ).toColor(),
      glow: Color.lerp(const Color(0xFFFFFFFF), base, 0.12)!,
      dark: dark,
    );
  }
}

/// What a scene is played for: the bubble it belongs to, in the
/// coordinates of the area the scene covers.
class EffectOrigin {
  /// The bubble's bounds, or null when it is not on screen.
  final Rect? rect;

  /// The bubble's corners.
  final BorderRadius borderRadius;

  /// The bubble's text, for the scene that repeats it.
  final String text;

  const EffectOrigin({
    this.rect,
    this.text = '',
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });

  /// The bubble's outline, or null when it is not on screen.
  RRect? get rrect => switch (rect) {
    null => null,
    final rect => borderRadius.toRRect(rect),
  };

  /// The bubble's centre, or a point low on the sending side when the
  /// bubble is not on screen.
  Offset centerIn(Size size) =>
      rect?.center ?? Offset(size.width * 0.75, size.height * 0.8);
}

/// One play of an effect.
abstract class EffectScene {
  final EffectPalette palette;
  final EffectOrigin origin;
  final math.Random random;

  EffectScene(this.palette, this.origin, int seed) : random = math.Random(seed);

  /// How long the scene runs.
  Duration get duration;

  /// Paints the scene [t] seconds in.
  void paint(Canvas canvas, Size size, double t);

  /// How far the conversation under the scene is pushed [t] seconds in.
  Offset shake(double t) => Offset.zero;

  /// What the scene is felt as, timed from its start. Every time in it
  /// comes from the constants and the random picks the scene paints with,
  /// so a haptic lands on the frame of the beat it belongs to.
  HapticPattern get haptics => HapticPattern.none;

  /// Frees what the scene holds once it has played.
  void dispose() {}

  double get seconds => duration.inMicroseconds / 1e6;

  /// The scene for a screen [effect]; null for a bubble effect, which has
  /// no scene of its own except [SlamScene].
  static EffectScene? of(
    MessageEffect effect,
    EffectPalette palette,
    EffectOrigin origin, {
    int seed = 7,
  }) => switch (effect) {
    MessageEffect.echo => EchoScene(palette, origin, seed),
    MessageEffect.spotlight => SpotlightScene(palette, origin, seed),
    MessageEffect.balloons => BalloonsScene(palette, origin, seed),
    MessageEffect.confetti => ConfettiScene(palette, origin, seed),
    MessageEffect.love => LoveScene(palette, origin, seed),
    MessageEffect.lasers => LasersScene(palette, origin, seed),
    MessageEffect.fireworks => FireworksScene(palette, origin, seed),
    MessageEffect.celebration => CelebrationScene(palette, origin, seed),
    MessageEffect.shootingStar => ShootingStarScene(palette, origin, seed),
    MessageEffect.slam => SlamScene(palette, origin, seed),
    MessageEffect.loud ||
    MessageEffect.gentle ||
    MessageEffect.invisibleInk => null,
  };
}

double _unit(double x) => x.clamp(0.0, 1.0);

/// 0 to 1 while [t] goes from [from] to [to].
double _span(double t, double from, double to) =>
    _unit((t - from) / (to - from));

/// Rises over [fadeIn] seconds, holds, and falls over the last [fadeOut].
double _envelope(double t, double total, double fadeIn, double fadeOut) =>
    math.min(
      Easing.standard.transform(_unit(t / fadeIn)),
      Easing.standard.transform(_unit((total - t) / fadeOut)),
    );

void _scrim(Canvas canvas, Size size, Color color, double alpha) {
  if (alpha <= 0) return;
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = color.withValues(alpha: alpha),
  );
}

/// A four pointed star, the Material sparkle.
Path _sparkle(Offset center, double radius) {
  final path = Path();
  const waist = 0.22;
  for (var i = 0; i < 4; i++) {
    final a = i * math.pi / 2 - math.pi / 2;
    final tip = center + Offset(math.cos(a), math.sin(a)) * radius;
    final b = a + math.pi / 4;
    final inner = center + Offset(math.cos(b), math.sin(b)) * radius * waist;
    if (i == 0) path.moveTo(tip.dx, tip.dy);
    path.quadraticBezierTo(center.dx, center.dy, inner.dx, inner.dy);
    final next = a + math.pi / 2;
    final nextTip = center + Offset(math.cos(next), math.sin(next)) * radius;
    path.quadraticBezierTo(center.dx, center.dy, nextTip.dx, nextTip.dy);
  }
  return path..close();
}

/// A heart that fits a box [size] wide, centred on the origin.
Path _heart(double size) {
  final w = size, h = size * 0.92;
  final path = Path()
    ..moveTo(0, h * 0.5)
    ..cubicTo(-w * 0.12, h * 0.36, -w * 0.5, h * 0.12, -w * 0.5, -h * 0.16)
    ..cubicTo(-w * 0.5, -h * 0.38, -w * 0.34, -h * 0.5, -w * 0.2, -h * 0.5)
    ..cubicTo(-w * 0.1, -h * 0.5, -w * 0.02, -h * 0.44, 0, -h * 0.32)
    ..cubicTo(w * 0.02, -h * 0.44, w * 0.1, -h * 0.5, w * 0.2, -h * 0.5)
    ..cubicTo(w * 0.34, -h * 0.5, w * 0.5, -h * 0.38, w * 0.5, -h * 0.16)
    ..cubicTo(w * 0.5, h * 0.12, w * 0.12, h * 0.36, 0, h * 0.5)
    ..close();
  return path;
}

// ---------------------------------------------------------------- balloons

/// [x] is where a balloon starts across the screen and [drift] how far it
/// is carried as it rises, both in screen widths and both for a bubble on
/// the right: the scene mirrors them for one on the left.
class _Balloon {
  final double x, release, rise, scale, sway, swayRate, phase, drift;
  final Color color;
  const _Balloon(
    this.x,
    this.release,
    this.rise,
    this.scale,
    this.sway,
    this.swayRate,
    this.phase,
    this.drift,
    this.color,
  );
}

/// Balloons of every party colour are let go along the bottom edge one
/// after another and rise across the conversation, drifting to the far
/// side, the near ones large and fast, one of them close enough to fill
/// the view for a moment.
class BalloonsScene extends EffectScene {
  late final List<_Balloon> _balloons;

  /// How many balloons rise besides the near one.
  static const _count = 9;

  /// The seconds over which the balloons are let go.
  static const _letGoOver = 1.3;

  /// The scales a balloon can have, the near one aside.
  static const _smallest = 0.45, _largest = 1.2;

  BalloonsScene(super.palette, super.origin, super.seed) {
    final colors = palette.festive;
    // One balloon to each slice of the letting go, so no two leave on the
    // same frame and each can be felt apart from the next.
    // The near one has the third.
    const nearSlot = 2;
    double slice(double slot) => 0.08 + slot / (_count + 1) * _letGoOver;
    final slots = [
      for (var i = 0; i <= _count; i++)
        if (i != nearSlot) i,
    ]..shuffle(random);
    final balloons = <_Balloon>[
      for (var i = 0; i < _count; i++)
        () {
          final scale =
              _smallest + random.nextDouble() * (_largest - _smallest);
          return _Balloon(
            0.14 + (i + random.nextDouble() * 0.7) / _count * 0.84,
            slice(slots[i] + random.nextDouble() * 0.6),
            // The near ones cross faster.
            2.5 - scale * 0.5 + random.nextDouble() * 0.4,
            scale,
            8 + random.nextDouble() * 14,
            1.2 + random.nextDouble() * 1.6,
            random.nextDouble() * math.pi * 2,
            0.04 + random.nextDouble() * 0.16,
            colors[i % colors.length],
          );
        }(),
      // The near one, in the bubble's own colour.
      _Balloon(
        0.62,
        slice(nearSlot + 0.3),
        1.7,
        2.7,
        10,
        1.1,
        0.4,
        0.2,
        palette.bubble,
      ),
    ]..sort((a, b) => a.scale.compareTo(b.scale));
    _balloons = balloons;
  }

  @override
  Duration get duration => const Duration(milliseconds: 4200);

  /// How many balloons the scene lets go.
  int get balloonCount => _balloons.length;

  /// One haptic for every balloon, on the frame it is let go and its top
  /// comes over the bottom edge: a tick, firmer the larger the balloon, and
  /// a click for the near one.
  @override
  HapticPattern get haptics => HapticPattern([
    for (final b in _balloons)
      b.scale > _largest
          ? HapticBeat.after(HapticPrimitive.click, b.release, scale: 0.7)
          : HapticBeat.after(
              HapticPrimitive.tick,
              b.release,
              scale: 0.3 + 0.6 * (b.scale - _smallest) / (_largest - _smallest),
            ),
  ]);

  @override
  void paint(Canvas canvas, Size size, double t) {
    final base = size.shortestSide * 0.2;
    // The balloons lean to the bubble's side and are carried to the other.
    final mirrored = origin.centerIn(size).dx < size.width / 2;
    for (final b in _balloons) {
      final local = t - b.release;
      if (local < 0) continue;
      final w = base * b.scale;
      final h = w * 1.24;
      // From its top at the bottom edge to its string clear of the top.
      final travel = size.height + h * 2.3;
      // Let go and gathering speed, as a balloon does.
      final p = math.pow(local / b.rise, 1.35).toDouble();
      if (p > 1) continue;
      final y = size.height + h * 0.5 - travel * p;
      final swing = b.phase + local * b.swayRate;
      final across = b.x - b.drift * p;
      final x =
          size.width * (mirrored ? 1 - across : across) +
          math.sin(swing) * b.sway;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(math.cos(swing) * 0.07);
      _paintBalloon(canvas, w, h, b.color, math.sin(swing - 0.9));
      canvas.restore();
    }
  }

  /// A balloon [w] by [h] around the origin, its string trailing to the
  /// side [trail] (-1 to 1) leans to.
  void _paintBalloon(
    Canvas canvas,
    double w,
    double h,
    Color color,
    double trail,
  ) {
    final hsl = HSLColor.fromColor(color);
    final light = hsl
        .withLightness(math.min(0.9, hsl.lightness + 0.2))
        .toColor();
    final dark = hsl.withLightness(math.max(0, hsl.lightness - 0.18)).toColor();
    final string = Path()
      ..moveTo(0, h * 0.56)
      ..cubicTo(
        w * 0.14 * trail,
        h * 0.9,
        -w * 0.16 * trail,
        h * 1.2,
        w * 0.1 * trail,
        h * 1.55,
      );
    canvas.drawPath(
      string,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1, w * 0.012)
        ..color = dark.withValues(alpha: 0.6),
    );
    final knot = Path()
      ..moveTo(0, h * 0.47)
      ..lineTo(-w * 0.07, h * 0.58)
      ..lineTo(w * 0.07, h * 0.58)
      ..close();
    canvas.drawPath(knot, Paint()..color = dark);
    // Full at the top and drawn in towards the knot.
    final body = Path()
      ..moveTo(0, h * 0.5)
      ..cubicTo(-w * 0.2, h * 0.42, -w * 0.5, h * 0.16, -w * 0.5, -h * 0.1)
      ..cubicTo(-w * 0.5, -h * 0.34, -w * 0.28, -h * 0.5, 0, -h * 0.5)
      ..cubicTo(w * 0.28, -h * 0.5, w * 0.5, -h * 0.34, w * 0.5, -h * 0.1)
      ..cubicTo(w * 0.5, h * 0.16, w * 0.2, h * 0.42, 0, h * 0.5)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(-w * 0.16, -h * 0.2),
          w * 0.9,
          [light, color, dark],
          const [0, 0.5, 1],
        ),
    );
    // A pill of reflected light.
    canvas.save();
    canvas.translate(-w * 0.2, -h * 0.24);
    canvas.rotate(0.5);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w * 0.13, height: h * 0.26),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.5),
    );
    canvas.restore();
  }
}

// ---------------------------------------------------------------- confetti

class _Confetto {
  final double x, release, speed, size, sway, swayRate, phase, spin, tumble;
  final int shape;
  final Color color;
  const _Confetto(
    this.x,
    this.release,
    this.speed,
    this.size,
    this.sway,
    this.swayRate,
    this.phase,
    this.spin,
    this.tumble,
    this.shape,
    this.color,
  );
}

/// Confetti cut into Material's shapes (circle, pill, rounded square,
/// triangle, half circle) comes down from above, a few pieces first, then
/// thick, then thinning, for as long as the scene runs, tumbling as it
/// falls.
class ConfettiScene extends EffectScene {
  late final List<_Confetto> _pieces;

  /// The seconds over which the confetti is let go, most of it around the
  /// middle of them.
  static const _pourOver = 2.5;

  /// How much speed a piece gains each second, in screen heights.
  static const _gravity = 0.1;

  /// A piece falls from this far above the top edge to this far below the
  /// bottom one, in screen heights.
  static const _above = 0.05, _below = 1.05;

  /// The length of one step of the rumble, in seconds.
  static const _grain = 0.07;

  ConfettiScene(super.palette, super.origin, super.seed) {
    final colors = palette.festive;
    _pieces = [
      for (var i = 0; i < 260; i++)
        _Confetto(
          random.nextDouble(),
          (random.nextDouble() + random.nextDouble()) / 2 * _pourOver,
          0.44 + random.nextDouble() * 0.3,
          8 + random.nextDouble() * 10,
          6 + random.nextDouble() * 22,
          1.5 + random.nextDouble() * 3,
          random.nextDouble() * math.pi * 2,
          (random.nextDouble() - 0.5) * 9,
          3 + random.nextDouble() * 7,
          random.nextInt(5),
          colors[random.nextInt(colors.length)],
        ),
    ];
    _grainJitter = [for (var i = 0; i < 128; i++) random.nextDouble()];
  }

  late final List<double> _grainJitter;

  @override
  Duration get duration => const Duration(milliseconds: 4400);

  /// How far down the screen [c] is [local] seconds after it was let go,
  /// in screen heights: thrown down, then held back less and less.
  static double _fallen(_Confetto c, double local) =>
      -_above + c.speed * local + _gravity * local * local;

  /// How long [c] takes to fall out of view.
  static double _airtime(_Confetto c) =>
      (-c.speed +
          math.sqrt(c.speed * c.speed + 4 * _gravity * (_above + _below))) /
      (2 * _gravity);

  /// The share of the confetti in the air [t] seconds in, against the most
  /// there ever is.
  List<double> get _density {
    final steps = (seconds / _grain).ceil();
    final counts = List.filled(steps, 0);
    for (final c in _pieces) {
      final from = (c.release / _grain).floor();
      final to = ((c.release + _airtime(c)) / _grain).ceil();
      for (var i = from; i < to && i < steps; i++) {
        counts[i]++;
      }
    }
    final most = counts.reduce(math.max);
    return [for (final count in counts) count / most];
  }

  /// A rumble for as long as confetti is in the air, as strong as the air
  /// is full: a run of ticks, sharp and low in turn and no two alike, or on
  /// a phone without them a grainy hum of the same shape.
  @override
  HapticPattern get haptics {
    final density = _density;
    return HapticPattern(
      [
        for (var i = 0; i < density.length; i++)
          if (density[i] > 0.04)
            HapticBeat.after(
              i.isEven ? HapticPrimitive.tick : HapticPrimitive.lowTick,
              i * _grain,
              scale:
                  0.12 +
                  0.5 * density[i] +
                  0.14 * _grainJitter[i % _grainJitter.length],
            ),
      ],
      envelope: HapticEnvelope.through([
        for (var i = 0; i < density.length; i += 4)
          (i * _grain, density[i] > 0.04 ? 0.08 + 0.3 * density[i] : 0.0),
        (seconds, 0),
      ], texture: 0.5),
    );
  }

  @override
  void paint(Canvas canvas, Size size, double t) {
    final paint = Paint();
    for (final c in _pieces) {
      final local = t - c.release;
      if (local < 0) continue;
      final fallen = _fallen(c, local);
      if (fallen > _below) continue;
      final x =
          size.width * c.x + math.sin(c.phase + local * c.swayRate) * c.sway;
      paint.color = c.color;
      canvas.save();
      canvas.translate(x, size.height * fallen);
      canvas.rotate(c.phase + local * c.spin);
      // Turning edge on makes a piece thin, which reads as tumbling.
      canvas.scale(1, math.cos(c.phase + local * c.tumble));
      final s = c.size;
      switch (c.shape) {
        case 0:
          canvas.drawCircle(Offset.zero, s * 0.5, paint);
        case 1:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset.zero,
                width: s * 1.5,
                height: s * 0.55,
              ),
              Radius.circular(s),
            ),
            paint,
          );
        case 2:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: s, height: s),
              Radius.circular(s * 0.28),
            ),
            paint,
          );
        case 3:
          canvas.drawPath(
            Path()
              ..moveTo(0, -s * 0.6)
              ..lineTo(s * 0.6, s * 0.45)
              ..lineTo(-s * 0.6, s * 0.45)
              ..close(),
            paint,
          );
        default:
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset.zero,
              width: s * 1.3,
              height: s * 1.3,
            ),
            0,
            math.pi,
            true,
            paint,
          );
      }
      canvas.restore();
    }
  }
}

// -------------------------------------------------------------------- love

/// A heart is pumped up out of the bubble, a beat at a time, lets go and
/// drifts up and away, a few small ones in its wake.
class LoveScene extends EffectScene {
  late final List<(double dx, double delay, double scale, double phase)> _small;

  LoveScene(super.palette, super.origin, super.seed) {
    _small = [
      for (var i = 0; i < 8; i++)
        (
          (random.nextDouble() - 0.5) * 0.8,
          _letGo - 0.1 + random.nextDouble() * 1.0,
          0.12 + random.nextDouble() * 0.14,
          random.nextDouble() * math.pi * 2,
        ),
    ];
  }

  @override
  Duration get duration => const Duration(milliseconds: 3600);

  /// The heart's beats, in seconds, with the size it has pumped up to
  /// after each (of its full size): two heartbeats, each a strong beat and
  /// a weaker one a thud's length (300 ms on a Pixel) and a little after.
  static const _beats = [(0.1, 0.38), (0.42, 0.5), (0.86, 0.88), (1.18, 1.0)];

  /// How long the heart takes to fill out after a beat.
  static const _pump = 0.26;

  /// When the heart lets go of the bubble.
  static const _letGo = 1.55;

  /// The heartbeat, a thud on each beat of the heart, the second of each
  /// pair softer, and a low tick as the heart lets go.
  @override
  HapticPattern get haptics => HapticPattern([
    for (final (i, (at, _)) in _beats.indexed)
      HapticBeat.after(
        HapticPrimitive.thud,
        at,
        scale: i.isEven ? (i == 0 ? 0.8 : 1.0) : 0.5,
      ),
    HapticBeat.after(HapticPrimitive.lowTick, _letGo, scale: 0.5),
  ]);

  @override
  void paint(Canvas canvas, Size size, double t) {
    final from = origin.centerIn(size);
    final full = size.shortestSide * 0.74;
    final hsl = HSLColor.fromColor(palette.love);
    final light = hsl
        .withLightness(math.min(0.72, hsl.lightness + 0.13))
        .toColor();
    final deep = hsl.withLightness(math.max(0, hsl.lightness - 0.16)).toColor();

    void heart(Offset at, double width, double angle, double alpha) {
      if (alpha <= 0 || width <= 0) return;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle);
      final path = _heart(width);
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(-width * 0.16, -width * 0.18),
            width * 0.95,
            [
              light.withValues(alpha: alpha),
              palette.love.withValues(alpha: alpha),
              deep.withValues(alpha: alpha),
            ],
            const [0, 0.42, 1],
          ),
      );
      // A pill of reflected light on the upper left lobe.
      canvas.translate(-width * 0.25, -width * 0.24);
      canvas.rotate(-0.6);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: width * 0.17,
          height: width * 0.08,
        ),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.6 * alpha),
      );
      canvas.restore();
    }

    for (final (dx, delay, scale, phase) in _small) {
      final local = t - delay;
      if (local < 0) continue;
      final p = _unit(local / 1.9);
      final at = Offset(
        from.dx + size.width * dx * p + math.sin(phase + local * 3) * 10,
        from.dy - size.height * 0.8 * Easing.standardAccelerate.transform(p),
      );
      heart(
        at,
        full *
            scale *
            Easing.emphasizedDecelerate.transform(_unit(local / 0.4)),
        math.sin(phase + local * 2.2) * 0.25,
        1 - _span(p, 0.75, 1),
      );
    }

    // Each beat pumps the heart up to its next size, with a little spring.
    // It grows up out of the bubble and, as it fills out, moves in from
    // the edge far enough to fit on screen.
    var grown = 0.07;
    for (final (at, to) in _beats) {
      if (t < at) break;
      grown +=
          (to - grown) * Curves.easeOutBack.transform(_unit((t - at) / _pump));
    }
    final width = full * grown;
    final away = t - _letGo;
    final fits = from.dx
        .clamp(
          math.min(width / 2 + 8, size.width / 2),
          math.max(size.width - width / 2 - 8, size.width / 2),
        )
        .toDouble();
    var center = Offset(fits, from.dy - width * 0.46);
    var angle = 0.0;
    var alpha = _unit(t / 0.1);
    if (away > 0) {
      final p = Easing.emphasizedAccelerate.transform(
        _unit(away / (seconds - _letGo)),
      );
      center += Offset(
        math.sin(away * 1.9) * size.width * 0.07 -
            (fits - size.width / 2) * 0.5 * p,
        -(size.height + full) * p,
      );
      angle = math.sin(away * 1.9) * 0.12;
      alpha = 1 - _span(t, seconds - 0.3, seconds);
    }
    heart(center, width, angle, alpha);
  }
}

// ------------------------------------------------------------------ lasers

class _Beam {
  final double angle, swing, width, hue;
  final int seed;
  const _Beam(this.angle, this.swing, this.width, this.hue, this.seed);
}

/// The room goes dark, a glow gathers behind the bubble and beams of light
/// fan out from it. They flash on a fast pulse, jump to new angles on
/// every fourth one, and the whole room's colour turns round the wheel.
/// The bubble itself is left out of the dark and of the beams, so the
/// message reads throughout.
class LasersScene extends EffectScene {
  late final List<_Beam> _beams;

  LasersScene(super.palette, super.origin, super.seed) {
    _beams = [
      for (var i = 0; i < 12; i++)
        _Beam(
          i / 12 * math.pi * 2,
          0.2 + random.nextDouble() * 0.45,
          0.01 + random.nextDouble() * 0.022,
          random.nextDouble(),
          random.nextInt(1 << 20),
        ),
    ];
  }

  @override
  Duration get duration => const Duration(milliseconds: 5000);

  /// How long the room takes to go dark, in seconds.
  static const _dark = 0.2;

  /// When the beams come on, the glow behind the bubble having gathered.
  static const _ignite = 0.8;

  /// The seconds between two pulses of the beams.
  static const _pulse = 0.15;

  /// How many pulses there are to a bar; the beams jump on the first.
  static const _bar = 4;

  /// How many pulses the beams play.
  static const _pulses = 22;

  /// How long the room takes to light up again once the beams are off.
  static const _fadeOut = 0.6;

  /// When the beams go off, after a last flash.
  double get _off => _ignite + _pulses * _pulse;

  /// The pulses the beams flash on, in seconds.
  List<double> get pulseTimes => [
    for (var i = 0; i < _pulses; i++) _ignite + i * _pulse,
  ];

  /// A slow rise as the glow gathers, a click as the beams come on and on
  /// the first pulse of every bar, a tick on each pulse between, and a
  /// last click as the beams go off.
  @override
  HapticPattern get haptics => HapticPattern([
    HapticBeat.after(
      HapticPrimitive.slowRise,
      _ignite,
      scale: 0.4,
      endsAt: true,
    ),
    for (final (i, at) in pulseTimes.indexed)
      i % _bar == 0
          ? HapticBeat.after(
              HapticPrimitive.click,
              at,
              scale: i == 0 ? 0.9 : 0.6,
            )
          : HapticBeat.after(HapticPrimitive.tick, at, scale: 0.55),
    HapticBeat.after(HapticPrimitive.click, _off, scale: 0.8),
  ], envelope: HapticEnvelope.swell(_dark, _ignite, _ignite + 0.1, level: 0.2));

  /// Where everything of the scene is painted: all of [size] but the
  /// bubble.
  Path paintedRegion(Size size) {
    final path = Path()..addRect(Offset.zero & size);
    final bubble = origin.rrect;
    if (bubble != null) {
      path
        ..addRRect(bubble)
        ..fillType = PathFillType.evenOdd;
    }
    return path;
  }

  /// A beam's lean in bar number [bar], -1 to 1.
  static double _leanAt(_Beam b, int bar) =>
      math.sin((b.seed % 997) * 0.37 + bar * 2.4 + (b.seed % 13) * bar);

  @override
  void paint(Canvas canvas, Size size, double t) {
    final env = math.min(
      Easing.standard.transform(_unit(t / _dark)),
      1 -
          Easing.standard.transform(
            _span(t, _off + 0.1, _off + 0.1 + _fadeOut),
          ),
    );
    canvas.save();
    canvas.clipPath(paintedRegion(size));
    _scrim(canvas, size, palette.scrim, 0.84 * env);
    final from = origin.centerIn(size);
    final reach = size.longestSide * 1.5;
    // The whole room turns once round the colour wheel while the beams
    // play, starting from the bubble's hue.
    final turned =
        HSLColor.fromColor(palette.bubble).hue +
        360 * _unit((t - _dark) / (_off - _dark));
    final paint = Paint()..blendMode = BlendMode.plus;
    final since = t - _ignite;
    final playing = since >= 0 && t < _off + 0.1;
    // Bright on each pulse, falling away until the next; the last flash,
    // as the beams go off, is the brightest.
    final into = since % _pulse;
    final flash = !playing
        ? 0.0
        : t >= _off
        ? 1.3 * (1 - (t - _off) / 0.1)
        : 0.5 + 0.5 * math.exp(-14 * into);
    if (playing) {
      final bar = (since / (_pulse * _bar)).floor();
      final jump = Easing.emphasizedDecelerate.transform(
        _unit((since - bar * _pulse * _bar) / (_pulse * 2.5)),
      );
      for (final b in _beams) {
        final lean = bar == 0
            ? _leanAt(b, 0)
            : ui.lerpDouble(_leanAt(b, bar - 1), _leanAt(b, bar), jump)!;
        final a = b.angle + lean * b.swing + t * 0.12;
        final color = HSLColor.fromAHSL(
          1,
          (turned + b.hue * 50) % 360,
          1,
          0.58,
        ).toColor();
        final dx = math.cos(a), dy = math.sin(a);
        final end = from + Offset(dx, dy) * reach;
        // A wide soft cone, and a thin hot core down its middle.
        for (final (half, strength, white) in [
          (b.width, 0.5, 0.0),
          (b.width * 0.22, 0.95, 0.65),
        ]) {
          final side = Offset(-dy, dx) * (reach * math.tan(half));
          canvas.drawPath(
            Path()
              ..moveTo(from.dx, from.dy)
              ..lineTo(end.dx - side.dx, end.dy - side.dy)
              ..lineTo(end.dx + side.dx, end.dy + side.dy)
              ..close(),
            paint
              ..shader = ui.Gradient.radial(
                from,
                reach,
                [
                  Color.lerp(
                    color,
                    palette.glow,
                    white,
                  )!.withValues(alpha: math.min(1, strength * env * flash)),
                  color.withValues(
                    alpha: math.min(1, strength * 0.6 * env * flash),
                  ),
                  color.withValues(alpha: 0),
                ],
                const [0, 0.3, 1],
              ),
          );
        }
      }
    }
    // The glow behind the bubble: gathering before the beams come on,
    // pulsing with them after, spilling round the bubble's edge.
    final gathered = Easing.standardAccelerate.transform(
      _span(t, _dark, _ignite),
    );
    final halo =
        ((origin.rect?.longestSide ?? 120) * 0.5 + 30) * (0.5 + 0.7 * gathered);
    final glowColor = HSLColor.fromAHSL(1, turned % 360, 1, 0.62).toColor();
    canvas.drawCircle(
      from,
      halo,
      paint
        ..shader = ui.Gradient.radial(from, halo, [
          Color.lerp(glowColor, palette.glow, 0.5)!.withValues(
            alpha: math.min(
              1,
              env * gathered * (playing ? 0.5 + 0.4 * flash : 0.8),
            ),
          ),
          glowColor.withValues(alpha: 0),
        ]),
    );
    canvas.restore();
  }
}

// --------------------------------------------------------------- fireworks

class _Spark {
  final double angle, speed, droop, twinkle;
  const _Spark(this.angle, this.speed, this.droop, this.twinkle);
}

class _Shell {
  final double at, x, y, radius;
  final Color color;
  final List<_Spark> sparks;
  const _Shell(this.at, this.x, this.y, this.radius, this.color, this.sparks);
}

/// The conversation goes dark and shells climb and burst one after
/// another, each a sphere of long bright streaks that slow, droop and
/// glitter out.
class FireworksScene extends EffectScene {
  late final List<_Shell> _shells;

  FireworksScene(super.palette, super.origin, super.seed) {
    // Far enough apart that each shell leaves the ground after the thud
    // of the one before it has rung out (300 ms on a Pixel).
    const times = [0.5, 1.3, 2.1, 2.9, 3.8, 4.6];
    _shells = [
      for (var i = 0; i < times.length; i++)
        _Shell(
          times[i],
          0.16 + random.nextDouble() * 0.68,
          0.14 + random.nextDouble() * 0.42,
          0.36 + random.nextDouble() * 0.24,
          // Mostly light itself, tinted by an accent.
          Color.lerp(
            palette.glow,
            palette.accents[i % palette.accents.length],
            0.35 + random.nextDouble() * 0.45,
          )!,
          [
            for (var k = 0; k < 120; k++)
              _Spark(
                random.nextDouble() * math.pi * 2,
                // Points on a sphere seen flat: dense at the rim.
                math.sqrt(1 - math.pow(random.nextDouble(), 2)) *
                    (0.86 + random.nextDouble() * 0.14),
                0.6 + random.nextDouble() * 0.8,
                random.nextDouble() * math.pi * 2,
              ),
          ],
        ),
    ];
  }

  @override
  Duration get duration => const Duration(milliseconds: 6600);

  /// A low tick as each shell leaves the ground and a thud as it bursts,
  /// the big ones harder.
  @override
  HapticPattern get haptics => HapticPattern([
    for (final shell in _shells) ...[
      HapticBeat.after(HapticPrimitive.lowTick, shell.at - _climb, scale: 0.4),
      HapticBeat.after(
        HapticPrimitive.thud,
        shell.at,
        scale: 0.5 + (shell.radius - 0.36) / 0.24 * 0.5,
      ),
    ],
  ]);

  static const _climb = 0.45;
  static const _life = 1.9;

  @override
  void paint(Canvas canvas, Size size, double t) {
    final env = _envelope(t, seconds, 0.3, 0.8);
    _scrim(canvas, size, palette.scrim, 0.8 * env);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    final fill = Paint()..blendMode = BlendMode.plus;
    for (final shell in _shells) {
      final burst = Offset(size.width * shell.x, size.height * shell.y);
      final rise = t - (shell.at - _climb);
      if (rise < 0) continue;
      if (rise < _climb) {
        // The climb: a thin tail up from the bottom edge.
        final p = Easing.standardDecelerate.transform(rise / _climb);
        final head = Offset(
          burst.dx,
          size.height + (burst.dy - size.height) * p,
        );
        final tail = Offset(
          burst.dx,
          size.height + (burst.dy - size.height) * math.max(0, p - 0.16),
        );
        canvas.drawLine(
          tail,
          head,
          line
            ..strokeWidth = 2
            ..shader = ui.Gradient.linear(tail, head, [
              shell.color.withValues(alpha: 0),
              shell.color.withValues(alpha: 0.9),
            ]),
        );
        continue;
      }
      line.shader = null;
      final local = t - shell.at;
      if (local > _life) continue;
      final radius = size.shortestSide * shell.radius;
      if (local < 0.18) {
        final flash = 1 - local / 0.18;
        canvas.drawCircle(
          burst,
          radius * (0.2 + 0.5 * (1 - flash)),
          fill
            ..shader = ui.Gradient.radial(burst, radius * 0.7, [
              palette.glow.withValues(alpha: 0.85 * flash),
              shell.color.withValues(alpha: 0),
            ]),
        );
      }
      fill.shader = null;
      final fade = 1 - _span(local, _life * 0.55, _life);
      // The burst lights the smoke around it.
      canvas.drawCircle(
        burst,
        radius * 1.1,
        fill
          ..shader = ui.Gradient.radial(burst, radius * 1.1, [
            shell.color.withValues(alpha: 0.22 * fade * (1 - local / _life)),
            shell.color.withValues(alpha: 0),
          ]),
      );
      fill.shader = null;
      // Fast out of the burst, then held back by the air.
      double reach(double at) => 1 - math.exp(-3.4 * math.max(0, at));
      for (final s in shell.sparks) {
        Offset at(double time) {
          final r = radius * s.speed * reach(time);
          return burst +
              Offset(
                math.cos(s.angle) * r,
                math.sin(s.angle) * r + radius * 0.22 * s.droop * time * time,
              );
        }

        final head = at(local);
        final tail = at(local - 0.2 - 0.14 * s.speed);
        final glitter = local > _life * 0.45
            ? 0.5 + 0.5 * math.sin(s.twinkle + local * 34)
            : 1.0;
        final alpha = fade * glitter;
        if (alpha <= 0.02) continue;
        canvas.drawLine(
          tail,
          head,
          line
            ..strokeWidth = 2.4
            ..color = shell.color.withValues(alpha: 0.8 * alpha),
        );
        canvas.drawCircle(
          head,
          1.9,
          fill..color = palette.glow.withValues(alpha: alpha),
        );
      }
    }
  }
}

// ------------------------------------------------------------- celebration

class _Ember {
  final double at, angle, speed, life, size, twinkle;
  final bool star;
  const _Ember(
    this.at,
    this.angle,
    this.speed,
    this.life,
    this.size,
    this.twinkle,
    this.star,
  );
}

/// A sparkler lit in the top corner of the sending side: a flickering
/// core throwing sparks that arc down across the dimmed conversation,
/// some of them four pointed sparkles.
class CelebrationScene extends EffectScene {
  late final List<_Ember> _embers;

  CelebrationScene(super.palette, super.origin, super.seed) {
    _embers = [
      for (var i = 0; i < 560; i++)
        _Ember(
          _lit + random.nextDouble() * (_burnsOut - _lit),
          random.nextDouble() * math.pi * 2,
          0.25 + random.nextDouble() * 0.75,
          0.6 + random.nextDouble() * 0.7,
          1.4 + random.nextDouble() * 2,
          random.nextDouble() * math.pi * 2,
          i % 9 == 0,
        ),
    ];
  }

  @override
  Duration get duration => const Duration(milliseconds: 4800);

  /// When the sparkler catches and when it burns out, in seconds.
  static const _lit = 0.2, _burnsOut = 3.5;

  /// The length of one step of the crackle, in seconds.
  static const _grain = 0.08;

  /// A click as the sparkler catches, then a crackle for as long as it
  /// burns: a tick for each step of time, as strong as the sparks thrown
  /// in it are many. A phone without the ticks gets a grainy hum.
  @override
  HapticPattern get haptics {
    final thrown = List.filled((seconds / _grain).ceil(), 0);
    for (final e in _embers) {
      thrown[(e.at / _grain).floor()]++;
    }
    final most = thrown.reduce(math.max);
    return HapticPattern(
      [
        HapticBeat.after(HapticPrimitive.click, _lit, scale: 0.5),
        for (final (i, count) in thrown.indexed)
          if (count > 0 && i * _grain > _lit + 0.05)
            HapticBeat.after(
              HapticPrimitive.tick,
              i * _grain,
              scale: 0.15 + 0.55 * count / most,
            ),
      ],
      envelope: HapticEnvelope.through([
        (_lit, 0),
        (_lit + 0.3, 0.25),
        (_burnsOut - 0.4, 0.2),
        (_burnsOut, 0),
      ], texture: 0.6),
    );
  }

  @override
  void paint(Canvas canvas, Size size, double t) {
    final env = _envelope(t, seconds, 0.35, 0.8);
    _scrim(canvas, size, palette.scrim, 0.78 * env);
    final from = Offset(size.width * 0.8, size.height * 0.16);
    final reach = size.shortestSide * 0.95;
    // Sparks burn the theme's tertiary, brightened to read as fire.
    final warm = Color.lerp(palette.glow, palette.accents[2], 0.7)!;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    final fill = Paint()..blendMode = BlendMode.plus;
    for (final e in _embers) {
      final local = t - e.at;
      if (local < 0 || local > e.life) continue;
      final p = local / e.life;
      Offset at(double time) {
        final r = reach * e.speed * (1 - math.exp(-2.6 * math.max(0, time)));
        return from +
            Offset(
              math.cos(e.angle) * r,
              math.sin(e.angle) * r + reach * 0.55 * time * time,
            );
      }

      final head = at(local);
      final alpha =
          (1 - p * p) * (0.6 + 0.4 * math.sin(e.twinkle + local * 40)) * env;
      if (e.star) {
        canvas.drawPath(
          _sparkle(head, e.size * 5 * (1 - p * 0.5)),
          fill..color = palette.glow.withValues(alpha: alpha),
        );
        continue;
      }
      canvas.drawLine(
        at(local - 0.11),
        head,
        line
          ..strokeWidth = e.size
          ..color = warm.withValues(alpha: alpha),
      );
    }
    final lit =
        _span(t, _lit - 0.1, _lit + 0.2) *
        (1 - _span(t, _burnsOut, _burnsOut + 0.5));
    final flicker = 0.8 + 0.2 * math.sin(t * 47) * math.sin(t * 31);
    final core = 46.0 * flicker;
    canvas.drawCircle(
      from,
      core,
      fill
        ..shader = ui.Gradient.radial(
          from,
          core,
          [
            palette.glow.withValues(alpha: lit),
            warm.withValues(alpha: 0.5 * lit),
            warm.withValues(alpha: 0),
          ],
          const [0, 0.3, 1],
        ),
    );
    fill.shader = null;
    canvas.drawPath(
      _sparkle(from, 26 * flicker * lit),
      fill..color = palette.glow.withValues(alpha: lit),
    );
  }
}

// ----------------------------------------------------------- shooting star

/// Night falls over the conversation and a star crosses it on a rising
/// arc, drawing a tail of light, then blooms and is gone.
class ShootingStarScene extends EffectScene {
  late final List<(double along, double off, double phase)> _dust;

  ShootingStarScene(super.palette, super.origin, super.seed) {
    _dust = [
      for (var i = 0; i < 26; i++)
        (
          random.nextDouble(),
          (random.nextDouble() - 0.5) * 26,
          random.nextDouble() * math.pi * 2,
        ),
    ];
  }

  @override
  Duration get duration => const Duration(milliseconds: 3400);

  static const _start = 0.35;
  static const _flight = 1.45;

  /// A slow rise through the last of the flight that peaks as the star
  /// lands, and a click as it blooms. A phone without the primitives
  /// swells over the flight and fades with the bloom.
  @override
  HapticPattern get haptics => HapticPattern(
    [
      HapticBeat.after(
        HapticPrimitive.slowRise,
        _start + _flight,
        scale: 0.4,
        endsAt: true,
      ),
      HapticBeat.after(HapticPrimitive.click, _start + _flight, scale: 0.7),
    ],
    envelope: HapticEnvelope.swell(
      _start,
      _start + _flight,
      _start + _flight + 0.5,
    ),
  );

  Offset _at(Size size, double p) {
    final a = Offset(-size.width * 0.08, size.height * 0.78);
    final c = Offset(size.width * 0.52, size.height * 0.7);
    final b = Offset(size.width * 0.82, size.height * 0.3);
    final q = 1 - p;
    return a * (q * q) + c * (2 * q * p) + b * (p * p);
  }

  @override
  void paint(Canvas canvas, Size size, double t) {
    final env = _envelope(t, seconds, 0.3, 0.7);
    final night = Color.lerp(palette.scrim, palette.bubble, 0.12)!;
    _scrim(canvas, size, night, 0.9 * env);
    final flown = _unit((t - _start) / _flight);
    final p = Easing.standardDecelerate.transform(flown);
    final tint = Color.lerp(palette.glow, palette.bubble, 0.35)!;
    final plus = Paint()..blendMode = BlendMode.plus;

    if (t > _start) {
      // The tail: the stretch of the arc just flown, thinning behind and
      // burning out once the star has landed.
      final burnt = _span(t, _start + _flight, _start + _flight + 0.7);
      final tailFrom = math.max(0.0, p - 0.55) + (p * burnt * 0.55);
      const steps = 28;
      for (var i = 0; i < steps; i++) {
        final u0 = tailFrom + (p - tailFrom) * i / steps;
        final u1 = tailFrom + (p - tailFrom) * (i + 1) / steps;
        final k = (i + 1) / steps;
        canvas.drawLine(
          _at(size, u0),
          _at(size, u1),
          plus
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 1 + 5.5 * k * k
            ..color = tint.withValues(alpha: 0.9 * k * (1 - burnt) * env),
        );
      }
      plus.style = PaintingStyle.fill;
      for (final (along, off, phase) in _dust) {
        if (along > p) continue;
        final age = t - (_start + along * _flight);
        final alpha =
            (1 - _unit(age / 1.3)) * (0.5 + 0.5 * math.sin(phase + t * 16));
        if (alpha <= 0) continue;
        canvas.drawPath(
          _sparkle(_at(size, along) + Offset(off * 0.4, off), 3.5),
          plus..color = palette.glow.withValues(alpha: alpha * env),
        );
      }
    }

    final head = _at(size, p);
    final landed = t - (_start + _flight);
    if (t > _start && landed < 0) {
      canvas.drawCircle(
        head,
        38,
        plus
          ..shader = ui.Gradient.radial(head, 38, [
            palette.glow.withValues(alpha: 0.9),
            tint.withValues(alpha: 0),
          ]),
      );
      plus.shader = null;
      canvas.drawPath(_sparkle(head, 20), plus..color = palette.glow);
    }
    if (landed >= 0) {
      // The bloom: a flash of the bubble's colour over the whole night.
      final bloom = Easing.emphasizedDecelerate.transform(_unit(landed / 0.5));
      final fade = 1 - _span(landed, 0.15, 1.1);
      final radius = size.longestSide * (0.08 + 0.9 * bloom);
      canvas.drawCircle(
        head,
        radius,
        plus
          ..shader = ui.Gradient.radial(
            head,
            radius,
            [
              palette.glow.withValues(alpha: 0.95 * fade),
              tint.withValues(alpha: 0.5 * fade),
              tint.withValues(alpha: 0),
            ],
            const [0, 0.25, 1],
          ),
      );
      plus.shader = null;
      canvas.drawPath(
        _sparkle(head, 30 * (1 + bloom) * fade),
        plus..color = palette.glow.withValues(alpha: fade),
      );
    }
  }
}

// --------------------------------------------------------------- spotlight

/// The conversation goes dark, then a lamp strikes overhead and throws a
/// wide circle of light around the bubble. The circle holds, breathing a
/// little, draws in for a moment and opens out over the whole conversation
/// as the light comes back.
class SpotlightScene extends EffectScene {
  late final List<(double along, double across, double phase)> _motes;

  SpotlightScene(super.palette, super.origin, super.seed) {
    _motes = [
      for (var i = 0; i < 18; i++)
        (
          0.15 + random.nextDouble() * 0.75,
          random.nextDouble() * 2 - 1,
          random.nextDouble() * math.pi * 2,
        ),
    ];
  }

  @override
  Duration get duration => const Duration(milliseconds: 4300);

  /// When the room has gone dark, in seconds.
  static const _dark = 0.35;

  /// When the lamp strikes and the circle is at full brightness.
  static const _on = 0.8;

  /// How long the lamp takes to come up to that.
  static const _strike = 0.1;

  /// When the circle has settled to its size.
  static const _settled = 1.1;

  /// When the circle starts to draw in, and when it opens out.
  static const _drawIn = 3.4, _open = 3.7;

  /// How long the circle takes to open over the whole conversation.
  static const _opening = 0.3;

  /// A slow rise through the dark that peaks with a click as the lamp
  /// strikes, and a quick rise into a second click as the circle opens
  /// out. A phone without the primitives swells into the strike.
  @override
  HapticPattern get haptics => HapticPattern(
    [
      HapticBeat.after(
        HapticPrimitive.slowRise,
        _on - _strike,
        scale: 0.35,
        endsAt: true,
      ),
      HapticBeat.after(HapticPrimitive.click, _on - _strike, scale: 0.8),
      HapticBeat.after(
        HapticPrimitive.quickRise,
        _open,
        scale: 0.4,
        endsAt: true,
      ),
      HapticBeat.after(HapticPrimitive.click, _open, scale: 0.6),
    ],
    envelope: HapticEnvelope.swell(_dark, _on - _strike, _on + 0.2, level: 0.2),
  );

  /// The bubble, or where one would be when it is not on screen.
  Rect _target(Size size) =>
      origin.rect ??
      Rect.fromCenter(center: origin.centerIn(size), width: 120, height: 44);

  /// The centre of the circle: the bubble's.
  Offset center(Size size) => _target(size).center;

  /// The radius of the circle at rest: a third of the screen's width, and
  /// more for a bubble that would not fit inside that with room to spare.
  double restRadius(Size size) => math.max(
    size.shortestSide * 0.33,
    _target(size).size.longestSide / 2 + 20,
  );

  /// The radius of the circle [t] seconds in.
  double radiusAt(Size size, double t) {
    final rest = restRadius(size);
    // Struck a little wide, settling, then breathing while it holds.
    final settle = Easing.emphasizedDecelerate.transform(
      _span(t, _on - _strike, _settled),
    );
    final breath =
        0.012 *
        math.sin((t - _settled) * 2.1) *
        _span(t, _settled, _settled + 0.4);
    final drawnIn = 0.04 * Easing.standard.transform(_span(t, _drawIn, _open));
    final opened = Easing.emphasizedAccelerate.transform(
      _span(t, _open, _open + _opening),
    );
    return rest * (1.05 - 0.05 * settle + breath - drawnIn) +
        size.longestSide * 1.2 * opened;
  }

  @override
  void paint(Canvas canvas, Size size, double t) {
    final dark =
        Easing.standard.transform(_unit(t / _dark)) *
        (1 - _span(t, _open + _opening * 0.5, seconds));
    // The lamp comes up fast, with a flicker as it strikes.
    final since = t - (_on - _strike);
    final lit = since < 0
        ? 0.0
        : _unit(since / _strike) *
              (since < 0.28 ? 0.86 + 0.14 * math.sin(since * 60) : 1);
    final at = center(size);
    final radius = radiusAt(size, t);
    final leaving = 1 - _span(t, _open, _open + _opening);

    // The dark, with the circle cut out of it. Its edge is soft over a
    // twelfth of its radius, as a lamp a little out of focus throws.
    canvas.saveLayer(Offset.zero & size, Paint());
    _scrim(canvas, size, palette.scrim, 0.88 * dark);
    if (lit > 0) {
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = ui.Gradient.radial(
            at,
            radius,
            [
              Color.fromRGBO(0, 0, 0, lit),
              Color.fromRGBO(0, 0, 0, lit),
              const Color(0x00000000),
            ],
            const [0, 0.88, 1],
          ),
      );
    }
    canvas.restore();
    if (lit <= 0) return;

    final plus = Paint()..blendMode = BlendMode.plus;
    final glow = lit * dark * leaving;
    // The beam: a cone of haze from the lamp, up in the corner across
    // from the bubble's side, down to the circle, with dust adrift in it.
    final lamp = Offset(
      at.dx > size.width / 2 ? size.width * 1.05 : -size.width * 0.05,
      -size.height * 0.08,
    );
    final axis = at - lamp;
    final normal = Offset(-axis.dy, axis.dx) / axis.distance;
    canvas.drawPath(
      Path()
        ..moveTo(lamp.dx - normal.dx * 10, lamp.dy - normal.dy * 10)
        ..lineTo(at.dx - normal.dx * radius, at.dy - normal.dy * radius)
        ..lineTo(at.dx + normal.dx * radius, at.dy + normal.dy * radius)
        ..lineTo(lamp.dx + normal.dx * 10, lamp.dy + normal.dy * 10)
        ..close(),
      plus
        ..shader = ui.Gradient.linear(lamp, at, [
          palette.glow.withValues(alpha: 0.3 * glow),
          palette.glow.withValues(alpha: 0.1 * glow),
        ]),
    );
    plus.shader = null;
    for (final (along, across, phase) in _motes) {
      final drift = along + 0.02 * math.sin(phase + t * 0.9);
      final mote =
          lamp +
          axis * drift +
          normal * (across * (10 + (radius - 10) * drift) * 0.85) +
          Offset(math.sin(phase + t * 1.3) * 3, 0);
      canvas.drawCircle(
        mote,
        0.9,
        plus
          ..color = palette.glow.withValues(
            alpha: glow * (0.25 + 0.25 * math.sin(phase * 3 + t * 2.4)),
          ),
      );
    }
    // The pool of light on the conversation, brightest in the middle. A
    // dark conversation shows no light by being uncovered, so there the
    // pool is painted on strongly. The bubble is left out of it and keeps
    // its own colours.
    final pool = palette.dark ? 0.42 : 0.1;
    canvas.save();
    final bubble = origin.rrect;
    if (bubble != null) {
      canvas.clipPath(
        Path()
          ..addRect(Offset.zero & size)
          ..addRRect(bubble)
          ..fillType = PathFillType.evenOdd,
      );
    }
    canvas.drawCircle(
      at,
      radius,
      plus
        ..shader = ui.Gradient.radial(
          at,
          radius,
          [
            palette.glow.withValues(alpha: pool * glow),
            palette.glow.withValues(alpha: pool * 0.7 * glow),
            palette.glow.withValues(alpha: 0),
          ],
          const [0, 0.88, 1],
        ),
    );
    canvas.restore();
  }
}

// -------------------------------------------------------------------- echo

class _Echo {
  final double appears, x, y, scale, drift;
  const _Echo(this.appears, this.x, this.y, this.scale, this.drift);
}

/// The bubble repeats itself: copies of it come up as specks all over the
/// conversation, one after another, and grow as they fly towards the
/// viewer and outwards, a few of them close enough to fill the view,
/// before they all thin out.
class EchoScene extends EffectScene {
  late final List<_Echo> _copies;

  /// One copy of the bubble with its text, drawn once, [_spriteScale]
  /// times its size so the large copies stay sharp.
  late final ui.Image _sprite;

  static const _spriteScale = 3.0;

  /// How many copies come up.
  static const _count = 48;

  /// The seconds over which they come up.
  static const _streamOver = 1.15;

  /// How long a copy flies for.
  static const _flight = 1.6;

  /// The scales a copy can grow to, the few that fly past close aside.
  static const _smallest = 0.35, _largest = 1.3;

  /// The scale a copy starts at: a speck.
  static const _speck = 0.1;

  EchoScene(super.palette, super.origin, super.seed) {
    final copies = <_Echo>[
      for (var i = 0; i < _count; i++)
        _Echo(
          // One to each slice of the stream, so every copy has a moment
          // of its own.
          (i + random.nextDouble() * 0.5) / _count * _streamOver,
          0.04 + random.nextDouble() * 0.92,
          0.04 + random.nextDouble() * 0.9,
          // Every twelfth flies past close.
          i % 12 == 7
              ? 3.2 + random.nextDouble() * 1.4
              : _smallest +
                    math.pow(random.nextDouble(), 1.6) * (_largest - _smallest),
          0.25 + random.nextDouble() * 0.5,
        ),
    ]..sort((a, b) => a.scale.compareTo(b.scale));
    _copies = copies;

    final text = origin.text.replaceAll('\n', ' ');
    final rect = origin.rect;
    final painter = TextPainter(
      text: TextSpan(
        text: text.length > 60 ? '${text.substring(0, 60)}…' : text,
        style: TextStyle(
          color: palette.onBubble,
          fontSize: 16,
          fontFamily: 'GoogleSansFlex',
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: math.max(40, (rect?.width ?? 252) - 32));
    final box = rect?.size ?? Size(painter.width + 32, painter.height + 20);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_spriteScale);
    canvas.drawRRect(
      (origin.rrect ??
              RRect.fromRectAndRadius(
                Offset.zero & box,
                Radius.circular(math.min(20, box.height / 2)),
              ))
          .shift(-(rect?.topLeft ?? Offset.zero)),
      Paint()..color = palette.bubble,
    );
    painter.paint(
      canvas,
      Offset(
        (box.width - painter.width) / 2,
        (box.height - painter.height) / 2,
      ),
    );
    painter.dispose();
    final picture = recorder.endRecording();
    _sprite = picture.toImageSync(
      math.max(1, (box.width * _spriteScale).ceil()),
      math.max(1, (box.height * _spriteScale).ceil()),
    );
    picture.dispose();
  }

  @override
  void dispose() => _sprite.dispose();

  @override
  Duration get duration => const Duration(milliseconds: 2900);

  /// How many copies come up.
  int get copyCount => _copies.length;

  /// One light tick for every copy, on the frame it comes up, firmer the
  /// larger the copy grows.
  @override
  HapticPattern get haptics => HapticPattern([
    for (final c in _copies)
      HapticBeat.after(
        HapticPrimitive.tick,
        c.appears,
        scale: math.min(
          0.9,
          0.3 + 0.4 * (c.scale - _smallest) / (_largest - _smallest),
        ),
      ),
  ]);

  @override
  void paint(Canvas canvas, Size size, double t) {
    final middle = size.center(Offset.zero);
    final transforms = <RSTransform>[];
    final colors = <Color>[];
    for (final c in _copies) {
      final local = t - c.appears;
      if (local < 0 || local > _flight) continue;
      final p = local / _flight;
      // Coming closer ever faster, as something flying at the eye does.
      final near = Easing.standardAccelerate.transform(p);
      final home = Offset(size.width * c.x, size.height * c.y);
      final at = home + (home - middle) * (c.drift * near * c.scale);
      // There at once, so the tick has something to land on, with a
      // little pop; gone quickly at the end.
      final pop = Curves.easeOutBack.transform(_unit(local / 0.22));
      final scale = _speck * pop + (c.scale - _speck) * near;
      final alpha = math.min(_unit(local / 0.03), 1 - _span(p, 0.82, 1)) * 0.96;
      transforms.add(
        RSTransform.fromComponents(
          rotation: 0,
          scale: scale / _spriteScale,
          anchorX: _sprite.width / 2,
          anchorY: _sprite.height / 2,
          translateX: at.dx,
          translateY: at.dy,
        ),
      );
      colors.add(Color.fromRGBO(255, 255, 255, alpha));
    }
    if (transforms.isEmpty) return;
    final whole = Rect.fromLTWH(
      0,
      0,
      _sprite.width.toDouble(),
      _sprite.height.toDouble(),
    );
    // Every copy in one draw.
    canvas.drawAtlas(
      _sprite,
      transforms,
      [for (var i = 0; i < transforms.length; i++) whole],
      colors,
      BlendMode.modulate,
      null,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
}

// -------------------------------------------------------------------- slam

/// What a slammed bubble does to the conversation around it: a ring of
/// pressure runs out from the bubble, dust jumps from its edges and
/// everything shakes once.
class SlamScene extends EffectScene {
  late final List<(double angle, double speed, double size)> _dust;

  SlamScene(super.palette, super.origin, super.seed) {
    _dust = [
      for (var i = 0; i < 22; i++)
        (
          random.nextDouble() * math.pi * 2,
          0.4 + random.nextDouble() * 0.6,
          1.5 + random.nextDouble() * 2.5,
        ),
    ];
  }

  @override
  Duration get duration => const Duration(milliseconds: 700);

  /// A heavy thud: the scene starts as the bubble lands.
  @override
  HapticPattern get haptics =>
      HapticPattern([HapticBeat.after(HapticPrimitive.thud, 0)]);

  @override
  Offset shake(double t) {
    // One hard knock that rings down.
    final decay = math.exp(-7 * t);
    return Offset(math.sin(t * 52) * 3 * decay, math.cos(t * 44) * 9 * decay);
  }

  @override
  void paint(Canvas canvas, Size size, double t) {
    final rect =
        origin.rect ??
        Rect.fromCenter(center: origin.centerIn(size), width: 120, height: 44);
    final p = Easing.emphasizedDecelerate.transform(_unit(t / seconds));
    final fade = 1 - _span(t, 0.1, seconds);
    final grown = rect.inflate(size.shortestSide * 0.55 * p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        grown,
        Radius.circular(20 + size.shortestSide * 0.55 * p),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10 * (1 - p) + 1
        ..color = palette.bubble.withValues(alpha: 0.45 * fade),
    );
    final dust = Paint();
    for (final (angle, speed, dotSize) in _dust) {
      final direction = Offset(math.cos(angle), math.sin(angle));
      final edge =
          rect.center +
          Offset(direction.dx * rect.width / 2, direction.dy * rect.height / 2);
      canvas.drawCircle(
        edge + direction * (90 * speed * p),
        dotSize * (1 - p * 0.5),
        dust..color = palette.bubble.withValues(alpha: 0.7 * fade),
      );
    }
  }
}
