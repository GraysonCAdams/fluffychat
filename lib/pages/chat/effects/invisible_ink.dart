// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/effect_haptics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// Hides [child], a message bubble, under ink until it is touched.
///
/// Hidden, nothing of the bubble's content is painted: the bubble is
/// covered edge to edge in fine, sharp specks that drift slowly and
/// twinkle (see [InkParticles]). A touch (or the mouse pointer) opens a
/// circle that grows from the finger across the bubble, the content
/// showing inside it and the specks scattering from its edge. The ink
/// closes again [concealAfter] after the finger lifts. A finger that
/// swipes over the ink while it is still clearing feels light ticks.
class InvisibleInk extends StatefulWidget {
  final Widget child;

  /// Painted behind the hidden content, so the bubble keeps its shape.
  final Color bubbleColor;

  /// The colour of the specks, the bubble's text colour.
  final Color dustColor;
  final BorderRadius borderRadius;

  /// Whether the specks move, the reveal animates and a swipe ticks. Off
  /// under reduced motion: the specks hold still and a touch reveals at
  /// once.
  final bool animate;

  const InvisibleInk({
    required this.child,
    required this.bubbleColor,
    required this.dustColor,
    required this.borderRadius,
    this.animate = true,
    super.key,
  });

  static const concealAfter = Duration(seconds: 5);

  /// How far a finger moves over the ink between two ticks.
  static const tickDistance = 14.0;

  @override
  State<InvisibleInk> createState() => InvisibleInkState();
}

class InvisibleInkState extends State<InvisibleInk>
    with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: Durations.long2,
    reverseDuration: Durations.extralong2,
  );
  late final Ticker _ticker = createTicker(
    (elapsed) => _time.value = elapsed.inMicroseconds / 1e6,
  );
  final _time = ValueNotifier<double>(0);
  final _particles = InkParticles(math.Random(3));
  Timer? _concealTimer;

  /// Where the bubble was last touched, the centre the reveal grows from.
  final _touch = ValueNotifier<Offset>(Offset.zero);

  /// Where the finger was at the last tick, while it is on the ink.
  Offset? _lastTick;

  /// Whether the whole bubble can be read.
  bool get isRevealed => _reveal.value == 1;

  /// Whether nothing of the bubble can be read.
  bool get isHidden => _reveal.value == 0;

  @override
  void initState() {
    super.initState();
    _reveal.addStatusListener((_) => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(InvisibleInk oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.animate && !_ticker.isActive) _ticker.start();
    if (!widget.animate && _ticker.isActive) _ticker.stop();
  }

  void _touchAt(Offset position) {
    _concealTimer?.cancel();
    _touch.value = position;
    if (!widget.animate) {
      _reveal.value = 1;
    } else if (_reveal.status != AnimationStatus.forward && !isRevealed) {
      _reveal.forward();
    }
  }

  /// Ticks when a finger lands on ink that is not yet clear, and again
  /// every [InvisibleInk.tickDistance] it moves until the ink has cleared.
  void _tickAt(Offset position, {required bool down}) {
    if (!widget.animate || isRevealed) return;
    final last = _lastTick;
    if (!down &&
        last != null &&
        (position - last).distance < InvisibleInk.tickDistance) {
      return;
    }
    _lastTick = position;
    EffectHaptics.instance.play(
      HapticPattern([
        HapticBeat(
          HapticPrimitive.tick,
          Duration.zero,
          scale: down ? 0.5 : 0.3,
        ),
      ]),
    );
  }

  void _release() {
    _lastTick = null;
    _concealTimer?.cancel();
    _concealTimer = Timer(InvisibleInk.concealAfter, conceal);
  }

  /// Covers the bubble again.
  void conceal() {
    _concealTimer?.cancel();
    if (!mounted) return;
    if (widget.animate) {
      _reveal.reverse();
    } else {
      _reveal.value = 0;
    }
  }

  @override
  void dispose() {
    _concealTimer?.cancel();
    _ticker.dispose();
    _reveal.dispose();
    _time.dispose();
    _touch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hidden = !isRevealed;
    return MouseRegion(
      onHover: (event) => _touchAt(event.localPosition),
      onExit: (_) => _release(),
      child: Listener(
        onPointerDown: (event) {
          _tickAt(event.localPosition, down: true);
          _touchAt(event.localPosition);
        },
        onPointerMove: (event) {
          _tickAt(event.localPosition, down: false);
          _touchAt(event.localPosition);
        },
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: Semantics(
          label: hidden ? L10n.of(context).invisibleInkHidden : null,
          child: ExcludeSemantics(
            excluding: hidden,
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: widget.bubbleColor)),
                  // The content, painted inside the reveal only.
                  ClipPath(
                    key: const ValueKey('invisible_ink_content'),
                    clipper: _RevealClipper(_reveal, _touch),
                    child: widget.child,
                  ),
                  if (hidden)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const ValueKey('invisible_ink_particles'),
                          painter: _InkPainter(
                            _particles,
                            _time,
                            _reveal,
                            _touch,
                            widget.dustColor,
                            MediaQuery.devicePixelRatioOf(context),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How far the reveal reaches from the touch [reveal] (0 to 1) of the way
/// through, over a bubble of [size]: at 1, past its farthest corner.
double _revealRadius(double reveal, Size size) =>
    Curves.easeInOutCubicEmphasized.transform(reveal) *
    (math.sqrt(size.width * size.width + size.height * size.height) +
        InkParticles.scatterBand);

/// Clips the hidden content to the circle the reveal has opened.
class _RevealClipper extends CustomClipper<Path> {
  final Animation<double> reveal;
  final ValueListenable<Offset> touch;

  _RevealClipper(this.reveal, this.touch)
    : super(reclip: Listenable.merge([reveal, touch]));

  @override
  Path getClip(Size size) {
    if (reveal.value >= 1) return Path()..addRect(Offset.zero & size);
    if (reveal.value <= 0) return Path();
    return Path()..addOval(
      Rect.fromCircle(
        center: touch.value,
        radius: _revealRadius(reveal.value, size),
      ),
    );
  }

  @override
  bool shouldReclip(_RevealClipper oldClipper) =>
      oldClipper.reveal != reveal || oldClipper.touch != touch;
}

/// The ink: a dense field of hard-edged specks, each a square one or one
/// and a half pixels across. Every speck circles its home slowly and
/// flickers at its own rate, some of them going dark between flashes. The
/// field is laid out on a unit square, so it fits a bubble of any size.
///
/// A frame is one `drawVertices` call: two triangles to a speck, coloured
/// at the vertices. Nothing is blurred and no image is built.
class InkParticles {
  /// The most specks a bubble is covered with.
  static const maxCount = 3200;

  /// How many square pixels of bubble there are to each speck.
  static const areaPerParticle = 5.5;

  /// How far a speck strays from its home, in pixels.
  static const drift = 3.5;

  /// The width of the ring outside an opening reveal in which specks thin
  /// out and are pushed away from it, in pixels.
  static const scatterBand = 22.0;

  /// Home position (x, y), phase and rate of each speck, all 0 to 1.
  final Float32List _specks = Float32List(maxCount * 4);

  /// The corners of every speck's square, four (x, y) pairs each.
  final Float32List positions = Float32List(maxCount * 8);

  /// The colour of each corner, as 0xAARRGGBB.
  final Int32List colors = Int32List(maxCount * 4);

  static final Uint16List _indices = () {
    final indices = Uint16List(maxCount * 6);
    for (var i = 0; i < maxCount; i++) {
      final v = i * 4;
      indices.setAll(i * 6, [v, v + 1, v + 2, v + 1, v + 3, v + 2]);
    }
    return indices;
  }();

  static final Float32List _sine = Float32List.fromList([
    for (var i = 0; i < 256; i++) math.sin(i / 256 * math.pi * 2),
  ]);

  /// The sine of [turns] full turns.
  static double _sin(double turns) => _sine[(turns * 256).floor() & 255];

  InkParticles(math.Random random) {
    for (var i = 0; i < _specks.length; i++) {
      _specks[i] = random.nextDouble();
    }
  }

  /// How many specks cover a bubble of [size].
  static int countFor(Size size) =>
      math.min(maxCount, (size.width * size.height / areaPerParticle).round());

  /// Works out where every speck is over [size] at [time] and how bright,
  /// into [positions] and [colors], and returns how many specks there are.
  ///
  /// Corners are snapped to the pixels of a screen with [devicePixelRatio]
  /// pixels to the logical pixel, so each speck is a sharp square. Specks
  /// within [clearRadius] of [clearCenter], where a reveal has opened, are
  /// left out; those in the [scatterBand] beyond it are dimmed and pushed
  /// outwards.
  int layout(
    Size size,
    double time,
    Color color, {
    double devicePixelRatio = 1,
    Offset clearCenter = Offset.zero,
    double clearRadius = 0,
  }) {
    final count = countFor(size);
    final rgb = color.toARGB32() & 0x00FFFFFF;
    final dpr = devicePixelRatio;
    var n = 0;
    for (var i = 0; i < count; i++) {
      final phase = _specks[i * 4 + 2];
      final rate = _specks[i * 4 + 3];
      // A slow circle round home: a turn every 3 to 7 seconds.
      final turn = phase + time * (0.14 + rate * 0.2);
      var x = _specks[i * 4] * size.width + _sin(turn + 0.25) * drift;
      var y = _specks[i * 4 + 1] * size.height + _sin(turn) * drift;
      // Flickering two to six times a second; the square of the wave
      // keeps a speck dim most of the time and bright in flashes.
      final wave = 0.5 + 0.5 * _sin(phase * 7 + time * (2 + rate * 4));
      var alpha = 0.22 + 0.78 * wave * wave;
      if (clearRadius > 0) {
        final dx = x - clearCenter.dx, dy = y - clearCenter.dy;
        final distance = math.sqrt(dx * dx + dy * dy);
        final beyond = distance - clearRadius;
        if (beyond <= 0) continue;
        if (beyond < scatterBand && distance > 0) {
          final near = 1 - beyond / scatterBand;
          x += dx / distance * near * 6;
          y += dy / distance * near * 6;
          alpha *= 1 - near;
        }
      }
      // One speck in three is a pixel and a half across, the rest one.
      final side = ((i % 3 == 0 ? 1.5 : 1.0) * dpr).round() / dpr;
      final left = (x * dpr).floor() / dpr;
      final top = (y * dpr).floor() / dpr;
      final p = n * 8;
      positions[p] = left;
      positions[p + 1] = top;
      positions[p + 2] = left + side;
      positions[p + 3] = top;
      positions[p + 4] = left;
      positions[p + 5] = top + side;
      positions[p + 6] = left + side;
      positions[p + 7] = top + side;
      final argb = ((color.a * alpha * 255).round() << 24) | rgb;
      colors.fillRange(n * 4, n * 4 + 4, argb);
      n++;
    }
    return n;
  }

  /// Paints the specks over [size] at [time] in one draw call.
  void paint(
    Canvas canvas,
    Size size,
    double time,
    Color color, {
    double devicePixelRatio = 1,
    Offset clearCenter = Offset.zero,
    double clearRadius = 0,
  }) {
    final n = layout(
      size,
      time,
      color,
      devicePixelRatio: devicePixelRatio,
      clearCenter: clearCenter,
      clearRadius: clearRadius,
    );
    if (n == 0) return;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(positions, 0, n * 8),
      colors: Int32List.sublistView(colors, 0, n * 4),
      indices: Uint16List.sublistView(_indices, 0, n * 6),
    );
    // BlendMode.dst keeps the colours of the vertices as they are.
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
  }
}

class _InkPainter extends CustomPainter {
  final InkParticles particles;
  final ValueListenable<double> time;
  final Animation<double> reveal;
  final ValueListenable<Offset> touch;
  final Color color;
  final double devicePixelRatio;

  _InkPainter(
    this.particles,
    this.time,
    this.reveal,
    this.touch,
    this.color,
    this.devicePixelRatio,
  ) : super(repaint: Listenable.merge([time, reveal, touch]));

  @override
  void paint(Canvas canvas, Size size) {
    particles.paint(
      canvas,
      size,
      time.value,
      color,
      devicePixelRatio: devicePixelRatio,
      clearCenter: touch.value,
      clearRadius: _revealRadius(reveal.value, size) - InkParticles.scatterBand,
    );
  }

  @override
  bool shouldRepaint(_InkPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
