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

  /// Accents for many-coloured effects, the bubble colour first.
  final List<Color> accents;

  /// What a dimmed conversation is dimmed with.
  final Color scrim;

  /// The warm accent of hearts.
  final Color love;

  /// The colour of light: sparks, stars and beams fade towards it.
  final Color glow;

  const EffectPalette({
    required this.bubble,
    required this.onBubble,
    required this.accents,
    required this.scrim,
    required this.love,
    required this.glow,
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
      scrim: Color.lerp(const Color(0xFF000000), scheme.primary, 0.08)!,
      love: scheme.error,
      glow: Color.lerp(const Color(0xFFFFFFFF), base, 0.12)!,
    );
  }
}

/// What a scene is played for: the bubble it belongs to, in the
/// coordinates of the area the scene covers.
class EffectOrigin {
  /// The bubble's bounds, or null when it is not on screen.
  final Rect? rect;

  /// The bubble's text, for the scene that repeats it.
  final String text;

  const EffectOrigin({this.rect, this.text = ''});

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

  /// What the scene is felt as, timed from its start to land on its beats.
  HapticPattern get haptics => HapticPattern.none;

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

class _Balloon {
  final double x, delay, rise, scale, sway, swayRate, phase, drift;
  final Color color;
  const _Balloon(
    this.x,
    this.delay,
    this.rise,
    this.scale,
    this.sway,
    this.swayRate,
    this.phase,
    this.drift,
    this.color,
  );
}

/// Balloons let go at the bottom of the sending side rise across the
/// conversation, the near ones large and fast, one of them close enough to
/// fill the view for a moment.
class BalloonsScene extends EffectScene {
  late final List<_Balloon> _balloons;

  BalloonsScene(super.palette, super.origin, super.seed) {
    final balloons = <_Balloon>[
      for (var i = 0; i < 16; i++)
        _Balloon(
          0.05 + random.nextDouble() * 0.9,
          random.nextDouble() * 1.5,
          1.9 + random.nextDouble() * 1.1,
          0.45 + random.nextDouble() * 0.75,
          8 + random.nextDouble() * 14,
          1.2 + random.nextDouble() * 1.6,
          random.nextDouble() * math.pi * 2,
          0.04 + random.nextDouble() * 0.16,
          palette.accents[i % palette.accents.length],
        ),
      // The near one.
      _Balloon(0.42, 0.35, 1.7, 2.7, 10, 1.1, 0.4, 0.2, palette.bubble),
    ]..sort((a, b) => a.scale.compareTo(b.scale));
    _balloons = balloons;
  }

  @override
  Duration get duration => const Duration(milliseconds: 4600);

  /// A soft tick as each balloon is let go, firmer for the near ones.
  /// Balloons let go within a tenth of a second of the last tick share it.
  @override
  HapticPattern get haptics {
    final beats = <HapticBeat>[];
    var last = double.negativeInfinity;
    for (final b in [
      ..._balloons,
    ]..sort((a, b) => a.delay.compareTo(b.delay))) {
      if (b.delay - last < 0.1) continue;
      last = b.delay;
      beats.add(
        HapticBeat.after(
          HapticPrimitive.tick,
          b.delay,
          scale: (0.15 + b.scale * 0.22).clamp(0.0, 0.8),
        ),
      );
    }
    return HapticPattern(beats);
  }

  @override
  void paint(Canvas canvas, Size size, double t) {
    final base = size.shortestSide * 0.2;
    for (final b in _balloons) {
      final local = t - b.delay;
      if (local < 0) continue;
      final w = base * b.scale;
      final h = w * 1.22;
      final travel = size.height + h * 2.6;
      // Let go and gathering speed, as a balloon does.
      final p = Easing.emphasizedAccelerate.transform(_unit(local / b.rise));
      final y = size.height + h * 0.7 - travel * p;
      if (y < -h * 2) continue;
      final x =
          size.width * (b.x + b.drift * p) +
          math.sin(b.phase + local * b.swayRate) * b.sway;
      final lean = math.cos(b.phase + local * b.swayRate) * 0.06;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(lean);
      _paintBalloon(canvas, w, h, b.color);
      canvas.restore();
    }
  }

  void _paintBalloon(Canvas canvas, double w, double h, Color color) {
    final hsl = HSLColor.fromColor(color);
    final light = hsl
        .withLightness(math.min(1, hsl.lightness + 0.22))
        .toColor();
    final dark = hsl.withLightness(math.max(0, hsl.lightness - 0.14)).toColor();
    final body = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    // The string, slack and trailing.
    final string = Path()
      ..moveTo(0, h * 0.56)
      ..cubicTo(w * 0.12, h * 0.9, -w * 0.12, h * 1.2, w * 0.04, h * 1.55);
    canvas.drawPath(
      string,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * 0.012)
        ..color = dark.withValues(alpha: 0.55),
    );
    final knot = Path()
      ..moveTo(0, h * 0.48)
      ..lineTo(-w * 0.07, h * 0.58)
      ..lineTo(w * 0.07, h * 0.58)
      ..close();
    canvas.drawPath(knot, Paint()..color = dark);
    canvas.drawOval(
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(-w * 0.18, -h * 0.22),
          w * 0.85,
          [light, color, dark],
          const [0, 0.55, 1],
        ),
    );
    // A soft pill of reflected light.
    canvas.save();
    canvas.translate(-w * 0.2, -h * 0.24);
    canvas.rotate(-0.5);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w * 0.14, height: h * 0.26),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.35),
    );
    canvas.restore();
  }
}

// ---------------------------------------------------------------- confetti

class _Confetto {
  final double x, delay, fall, size, sway, swayRate, phase, spin, tumble;
  final int shape;
  final Color color;
  const _Confetto(
    this.x,
    this.delay,
    this.fall,
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
/// triangle, half circle) pours from above, tumbling as it falls.
class ConfettiScene extends EffectScene {
  late final List<_Confetto> _pieces;

  ConfettiScene(super.palette, super.origin, super.seed) {
    _pieces = [
      for (var i = 0; i < 240; i++)
        _Confetto(
          random.nextDouble(),
          // Most of it lets go at once, the rest trails.
          math.pow(random.nextDouble(), 1.7) * 1.7,
          0.55 + random.nextDouble() * 0.5,
          8 + random.nextDouble() * 10,
          6 + random.nextDouble() * 22,
          1.5 + random.nextDouble() * 3,
          random.nextDouble() * math.pi * 2,
          (random.nextDouble() - 0.5) * 9,
          3 + random.nextDouble() * 7,
          random.nextInt(5),
          palette.accents[random.nextInt(palette.accents.length)],
        ),
    ];
  }

  @override
  Duration get duration => const Duration(milliseconds: 4400);

  /// A burst of light ticks as most of the confetti lets go at once.
  @override
  HapticPattern get haptics => HapticPattern([
    for (var i = 0; i < 8; i++)
      HapticBeat.after(HapticPrimitive.tick, i * 0.045, scale: 0.6 - i * 0.05),
  ]);

  @override
  void paint(Canvas canvas, Size size, double t) {
    final paint = Paint();
    for (final c in _pieces) {
      final local = t - c.delay;
      if (local < 0) continue;
      // Thrown down, then held back by the air.
      final y = -30 + size.height * (c.fall * local + 0.18 * local * local);
      if (y > size.height + 30) continue;
      final x =
          size.width * c.x + math.sin(c.phase + local * c.swayRate) * c.sway;
      final fadeOut = _span(t, seconds - 0.5, seconds);
      paint.color = c.color.withValues(alpha: 1 - fadeOut);
      canvas.save();
      canvas.translate(x, y);
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
            paint
              ..strokeJoin = StrokeJoin.round
              ..style = PaintingStyle.fill,
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

/// A heart swells out of the bubble like a balloon being blown, lets go and
/// drifts up and away, a few small ones in its wake.
class LoveScene extends EffectScene {
  late final List<(double dx, double delay, double scale, double phase)> _small;

  LoveScene(super.palette, super.origin, super.seed) {
    _small = [
      for (var i = 0; i < 6; i++)
        (
          (random.nextDouble() - 0.5) * 0.7,
          1.3 + random.nextDouble() * 0.9,
          0.14 + random.nextDouble() * 0.14,
          random.nextDouble() * math.pi * 2,
        ),
    ];
  }

  @override
  Duration get duration => const Duration(milliseconds: 4000);

  static const _swell = 1.25;

  /// How long each breath that blows the heart up takes.
  static const _breath = 0.62;

  /// Two beats, a heartbeat, on the heart's first breath. They are as far
  /// apart as a thud lasts on a Pixel (300 ms), so the second does not
  /// wait for the first to end.
  @override
  HapticPattern get haptics => HapticPattern([
    HapticBeat.after(HapticPrimitive.thud, _breath / 4, scale: 0.8),
    HapticBeat.after(HapticPrimitive.thud, _breath / 4 + 0.3, scale: 0.5),
  ]);

  @override
  void paint(Canvas canvas, Size size, double t) {
    final from = origin.centerIn(size);
    final full = size.shortestSide * 0.62;
    final hsl = HSLColor.fromColor(palette.love);
    final light = hsl
        .withLightness(math.min(0.82, hsl.lightness + 0.2))
        .toColor();
    final deep = hsl.withLightness(math.max(0, hsl.lightness - 0.12)).toColor();

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
            Offset(-width * 0.18, -width * 0.2),
            width * 0.9,
            [
              light.withValues(alpha: alpha),
              palette.love.withValues(alpha: alpha),
              deep.withValues(alpha: alpha),
            ],
            const [0, 0.5, 1],
          ),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(-width * 0.24, -width * 0.22),
          width: width * 0.16,
          height: width * 0.1,
        ),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.4 * alpha),
      );
      canvas.restore();
    }

    for (final (dx, delay, scale, phase) in _small) {
      final local = t - delay;
      if (local < 0) continue;
      final p = _unit(local / 1.8);
      final at = Offset(
        from.dx + size.width * dx * p + math.sin(phase + local * 3) * 10,
        from.dy - size.height * 0.75 * Easing.standardAccelerate.transform(p),
      );
      heart(
        at,
        full *
            scale *
            Easing.emphasizedDecelerate.transform(_unit(local / 0.4)),
        math.sin(phase + local * 2.2) * 0.25,
        1 - _span(p, 0.7, 1),
      );
    }

    // Blown up in two breaths, the bottom tip held at the bubble.
    final swell = Easing.emphasizedDecelerate.transform(_unit(t / _swell));
    final breath = 1 + 0.05 * math.sin(t * math.pi * 2 / _breath) * (1 - swell);
    final width = full * (0.08 + 0.92 * swell) * breath;
    final away = t - _swell;
    var center = from - Offset(0, width * 0.46);
    var angle = math.sin(t * 5) * 0.05 * (1 - swell);
    var alpha = _unit(t / 0.15);
    if (away > 0) {
      final p = Easing.emphasizedAccelerate.transform(
        _unit(away / (seconds - _swell)),
      );
      center += Offset(
        math.sin(away * 1.9) * size.width * 0.07 -
            (from.dx - size.width / 2) * 0.5 * p,
        -(size.height + full) * p,
      );
      angle = math.sin(away * 1.9 + 0.6) * 0.12;
      alpha = 1 - _span(t, seconds - 0.35, seconds);
    }
    heart(center, width, angle, alpha);
  }
}

// ------------------------------------------------------------------ lasers

class _Beam {
  final double angle, swing, rate, phase, width, hue;
  const _Beam(
    this.angle,
    this.swing,
    this.rate,
    this.phase,
    this.width,
    this.hue,
  );
}

/// The room goes dark and beams of light fan out from the bubble, sweeping
/// up and down while their colour turns.
class LasersScene extends EffectScene {
  late final List<_Beam> _beams;

  LasersScene(super.palette, super.origin, super.seed) {
    _beams = [
      for (var i = 0; i < 11; i++)
        _Beam(
          i / 11 * math.pi * 2,
          0.25 + random.nextDouble() * 0.5,
          1.4 + random.nextDouble() * 1.8,
          random.nextDouble() * math.pi * 2,
          0.012 + random.nextDouble() * 0.03,
          random.nextDouble(),
        ),
    ];
  }

  @override
  Duration get duration => const Duration(milliseconds: 4400);

  /// The beat the beams flicker to, in seconds.
  static const _beat = 0.7;

  /// A low pulse on every beat while the room is dark.
  @override
  HapticPattern get haptics => HapticPattern([
    for (var t = 0.35; t < seconds - 0.7; t += _beat)
      HapticBeat.after(HapticPrimitive.lowTick, t),
  ]);

  @override
  void paint(Canvas canvas, Size size, double t) {
    final env = _envelope(t, seconds, 0.35, 0.7);
    _scrim(canvas, size, palette.scrim, 0.8 * env);
    final from = origin.centerIn(size);
    final reach = size.longestSide * 1.5;
    final hsl = HSLColor.fromColor(palette.bubble);
    for (final b in _beams) {
      final a = b.angle + math.sin(b.phase + t * b.rate) * b.swing + t * 0.15;
      // Each beam walks the colour wheel, starting from the bubble's hue.
      final color = HSLColor.fromAHSL(
        1,
        (hsl.hue + b.hue * 70 + t * 55) % 360,
        0.95,
        0.6,
      ).toColor();
      final flicker =
          0.75 + 0.25 * math.sin(b.phase * 3 + t * math.pi * 2 / _beat);
      final half = b.width;
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(
          from.dx + math.cos(a - half) * reach,
          from.dy + math.sin(a - half) * reach,
        )
        ..lineTo(
          from.dx + math.cos(a + half) * reach,
          from.dy + math.sin(a + half) * reach,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(
            from,
            reach,
            [
              Color.lerp(
                color,
                palette.glow,
                0.6,
              )!.withValues(alpha: 0.9 * env * flicker),
              color.withValues(alpha: 0.55 * env * flicker),
              color.withValues(alpha: 0),
            ],
            const [0, 0.25, 1],
          ),
      );
    }
    canvas.drawCircle(
      from,
      70,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(from, 70, [
          palette.glow.withValues(alpha: 0.8 * env),
          palette.glow.withValues(alpha: 0),
        ]),
    );
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
    const times = [0.35, 1.0, 1.55, 2.4, 3.0, 3.7, 4.3];
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
  Duration get duration => const Duration(milliseconds: 6400);

  /// A thud as each shell bursts, the big ones harder.
  @override
  HapticPattern get haptics => HapticPattern([
    for (final shell in _shells)
      HapticBeat.after(
        HapticPrimitive.thud,
        shell.at,
        scale: 0.5 + (shell.radius - 0.36) / 0.24 * 0.5,
      ),
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
          0.2 + random.nextDouble() * 3.3,
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

  /// A burst of light ticks as the sparkler catches and its first sparks
  /// fly.
  @override
  HapticPattern get haptics => HapticPattern([
    for (var i = 0; i < 10; i++)
      HapticBeat.after(HapticPrimitive.tick, 0.2 + i * 0.06, scale: 0.5),
  ]);

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
    final lit = _span(t, 0.1, 0.4) * (1 - _span(t, 3.5, 4.0));
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

  /// A slow rise that peaks as the star lands, then a gentle tick as it
  /// blooms; on phones without the primitives, a swell over the flight
  /// that fades with the bloom.
  @override
  HapticPattern get haptics => HapticPattern(
    [
      HapticBeat.after(
        HapticPrimitive.slowRise,
        _start + _flight,
        scale: 0.35,
        endsAt: true,
      ),
      HapticBeat.after(HapticPrimitive.tick, _start + _flight, scale: 0.5),
    ],
    swell: HapticSwell.after(_start, _start + _flight, _start + _flight + 0.5),
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
    final p = Easing.emphasizedAccelerate.transform(flown);
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

/// The conversation dims and a spot of light swings onto the bubble and
/// rests there before the light comes back.
class SpotlightScene extends EffectScene {
  SpotlightScene(super.palette, super.origin, super.seed);

  @override
  Duration get duration => const Duration(milliseconds: 3800);

  /// When the spot comes to rest on the bubble, in seconds.
  static const _arrived = 1.0;

  /// A slow rise as the spot swings in, peaking as it comes to rest with a
  /// gentle tick; on phones without the primitives, a swell over the swing.
  @override
  HapticPattern get haptics => HapticPattern(
    [
      HapticBeat.after(
        HapticPrimitive.slowRise,
        _arrived,
        scale: 0.3,
        endsAt: true,
      ),
      HapticBeat.after(HapticPrimitive.tick, _arrived, scale: 0.5),
    ],
    swell: HapticSwell.after(0.15, _arrived, _arrived + 0.3, amplitude: 50),
  );

  @override
  void paint(Canvas canvas, Size size, double t) {
    final env = _envelope(t, seconds, 0.4, 0.7);
    final rect =
        origin.rect ??
        Rect.fromCenter(center: origin.centerIn(size), width: 120, height: 44);
    final radius = math.max(rect.width * 0.62, rect.height) + 28;
    // The spot arrives from above the far side and settles with a little
    // overshoot, as a lamp swung by hand does.
    final arrive = Curves.easeOutBack.transform(_span(t, 0.15, _arrived));
    final start = Offset(size.width - rect.center.dx, rect.center.dy - 260);
    final center = Offset.lerp(start, rect.center, arrive)!;
    final lamp = Offset(
      size.width / 2 + (center.dx - size.width / 2) * 0.2,
      -80,
    );

    canvas.saveLayer(Offset.zero & size, Paint());
    _scrim(canvas, size, palette.scrim, 0.78 * env);
    canvas.drawCircle(
      center,
      radius * 1.25,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = ui.Gradient.radial(
          center,
          radius * 1.25,
          const [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          const [0, 0.72, 1],
        ),
    );
    canvas.restore();

    // The beam: a cone of haze from the lamp to the spot.
    final axis = center - lamp;
    final normal = Offset(-axis.dy, axis.dx) / axis.distance;
    final cone = Path()
      ..moveTo(lamp.dx - normal.dx * 6, lamp.dy - normal.dy * 6)
      ..lineTo(center.dx - normal.dx * radius, center.dy - normal.dy * radius)
      ..lineTo(center.dx + normal.dx * radius, center.dy + normal.dy * radius)
      ..lineTo(lamp.dx + normal.dx * 6, lamp.dy + normal.dy * 6)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(lamp, center, [
          palette.glow.withValues(alpha: 0.2 * env),
          palette.glow.withValues(alpha: 0.05 * env),
        ]),
    );
  }
}

// -------------------------------------------------------------------- echo

class _Echo {
  final double delay, life, x, y, scale, bend;
  const _Echo(this.delay, this.life, this.x, this.y, this.scale, this.bend);
}

/// The bubble repeats itself: copies of every size stream out of it and
/// fill the conversation before they thin out.
class EchoScene extends EffectScene {
  late final List<_Echo> _copies;
  late final TextPainter _text;

  EchoScene(super.palette, super.origin, super.seed) {
    final copies = <_Echo>[
      for (var i = 0; i < 44; i++)
        _Echo(
          random.nextDouble() * 1.9,
          1.5 + random.nextDouble() * 0.9,
          random.nextDouble(),
          random.nextDouble() * 0.92,
          0.45 + math.pow(random.nextDouble(), 2) * 1.9,
          (random.nextDouble() - 0.5) * 0.5,
        ),
    ]..sort((a, b) => a.scale.compareTo(b.scale));
    _copies = copies;
    final text = origin.text.replaceAll('\n', ' ');
    _text = TextPainter(
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
    )..layout(maxWidth: 220);
  }

  @override
  Duration get duration => const Duration(milliseconds: 4200);

  /// One gentle tick as the copies start to stream out.
  @override
  HapticPattern get haptics => HapticPattern([
    HapticBeat.after(HapticPrimitive.tick, 0, scale: 0.5),
  ]);

  @override
  void paint(Canvas canvas, Size size, double t) {
    final from = origin.centerIn(size);
    final box = Size(
      origin.rect?.width ?? _text.width + 32,
      origin.rect?.height ?? _text.height + 20,
    );
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: box.width,
        height: box.height,
      ),
      Radius.circular(math.min(20, box.height / 2)),
    );
    final paint = Paint();
    for (final c in _copies) {
      final local = t - c.delay;
      if (local < 0 || local > c.life) continue;
      final p = local / c.life;
      final moved = Easing.emphasizedDecelerate.transform(p);
      final to = Offset(size.width * c.x, size.height * c.y);
      final middle =
          Offset.lerp(from, to, 0.5)! +
          Offset(-(to - from).dy, (to - from).dx) * c.bend;
      final q = 1 - moved;
      final at =
          from * (q * q) + middle * (2 * q * moved) + to * (moved * moved);
      final alpha = math.min(_unit(p / 0.12), 1 - _span(p, 0.6, 1)) * 0.92;
      final scale = 0.3 + (c.scale - 0.3) * moved;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.scale(scale);
      canvas.saveLayer(
        rrect.outerRect.inflate(2),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
      canvas.drawRRect(rrect, paint..color = palette.bubble);
      _text.paint(canvas, Offset(-_text.width / 2, -_text.height / 2));
      canvas.restore();
      canvas.restore();
    }
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
  HapticPattern get haptics => HapticPattern([HapticBeat.after(HapticPrimitive.thud, 0)]);

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
