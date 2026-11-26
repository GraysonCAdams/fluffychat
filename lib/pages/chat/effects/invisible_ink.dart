// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// Hides [child], a message bubble, under drifting dust until it is
/// touched.
///
/// Hidden, the bubble's content is blurred and shows only through the
/// specks of dust, so what can be seen is a shimmer in the shape of the
/// text. A touch (or the mouse pointer) opens a clear circle that grows
/// from the finger across the bubble while the blur pulls into focus. The
/// ink closes again [concealAfter] after the finger lifts.
class InvisibleInk extends StatefulWidget {
  final Widget child;

  /// Painted behind the hidden content, so the bubble keeps its shape.
  final Color bubbleColor;

  /// The colour of the loose dust, the bubble's text colour.
  final Color dustColor;
  final BorderRadius borderRadius;

  /// Whether the dust drifts and the reveal animates. Off under reduced
  /// motion: the dust holds still and a touch reveals at once.
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
  final _dust = _Dust(math.Random(3));
  Timer? _concealTimer;
  Offset _touch = Offset.zero;
  ui.Image? _mask;

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
    _touch = position;
    if (!widget.animate) {
      _reveal.value = 1;
    } else if (_reveal.status != AnimationStatus.forward && !isRevealed) {
      _reveal.forward();
    }
  }

  void _release() {
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
    _mask?.dispose();
    super.dispose();
  }

  /// The mask the content is seen through: opaque where it shows.
  ui.Shader _maskShader(Rect bounds) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = bounds.size;
    final reveal = Curves.easeInOutCubicEmphasized.transform(_reveal.value);
    if (reveal >= 1) {
      canvas.drawRect(Offset.zero & size, Paint());
    } else {
      _dust.paint(
        canvas,
        size,
        _time.value,
        const Color(0xFFFFFFFF),
        density: 1,
      );
      if (reveal > 0) {
        final radius =
            reveal *
            (math.sqrt(size.width * size.width + size.height * size.height) +
                24);
        canvas.drawCircle(
          _touch,
          radius,
          Paint()
            ..shader = ui.Gradient.radial(
              _touch,
              radius,
              const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
              const [0, 0.8, 1],
            ),
        );
      }
    }
    final image = recorder.endRecording().toImageSync(
      math.max(1, size.width.ceil()),
      math.max(1, size.height.ceil()),
    );
    _mask?.dispose();
    _mask = image;
    return ui.ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hidden = !isRevealed;
    return MouseRegion(
      onHover: (event) => _touchAt(event.localPosition),
      onExit: (_) => _release(),
      child: Listener(
        onPointerDown: (event) => _touchAt(event.localPosition),
        onPointerMove: (event) => _touchAt(event.localPosition),
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
                  AnimatedBuilder(
                    animation: Listenable.merge([_time, _reveal]),
                    builder: (context, child) {
                      final sigma =
                          7.0 *
                          (1 -
                              Curves.easeInOutCubicEmphasized.transform(
                                _reveal.value,
                              ));
                      return ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: _maskShader,
                        child: ImageFiltered(
                          enabled: sigma > 0.05,
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: sigma,
                            sigmaY: sigma,
                            tileMode: TileMode.decal,
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: widget.child,
                  ),
                  if (hidden)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _LooseDustPainter(
                            _dust,
                            _time,
                            _reveal,
                            widget.dustColor,
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

/// A field of specks, each circling a home position and twinkling, laid out
/// on a unit square so it fits a bubble of any size.
class _Dust {
  static const _count = 4000;
  final Float32List _specks = Float32List(_count * 4);

  _Dust(math.Random random) {
    for (var i = 0; i < _specks.length; i++) {
      _specks[i] = random.nextDouble();
    }
  }

  /// Paints the field over [size] at [time]. [density] 1 is the mask's
  /// thick dust; lower thins it by leaving specks out.
  void paint(
    Canvas canvas,
    Size size,
    double time,
    Color color, {
    required double density,
  }) {
    // About one speck to every 7 square pixels, up to the whole field.
    final count = math.min(
      _count,
      (size.width * size.height / 7 * density).round(),
    );
    const levels = 3;
    final points = [for (var i = 0; i < levels; i++) <Offset>[]];
    for (var i = 0; i < count; i++) {
      final phase = _specks[i * 4 + 2] * math.pi * 2;
      final rate = 0.8 + _specks[i * 4 + 3] * 2.2;
      final angle = phase + time * rate;
      final twinkle = math.sin(phase * 5 + time * (2 + rate * 2));
      points[twinkle > 0.3 ? 0 : (twinkle > -0.4 ? 1 : 2)].add(
        Offset(
          _specks[i * 4] * size.width + math.cos(angle) * 3.5,
          _specks[i * 4 + 1] * size.height + math.sin(angle) * 3.5,
        ),
      );
    }
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.3;
    const alphas = [1.0, 0.6, 0.25];
    for (var i = 0; i < levels; i++) {
      canvas.drawPoints(
        ui.PointMode.points,
        points[i],
        paint..color = color.withValues(alpha: color.a * alphas[i]),
      );
    }
  }
}

/// Dust lying over the whole bubble, so a short text still reads as a
/// bubble full of ink.
class _LooseDustPainter extends CustomPainter {
  final _Dust dust;
  final ValueListenable<double> time;
  final Animation<double> reveal;
  final Color color;

  _LooseDustPainter(this.dust, this.time, this.reveal, this.color)
    : super(repaint: Listenable.merge([time, reveal]));

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = 0.55 * (1 - reveal.value);
    if (alpha <= 0) return;
    dust.paint(
      canvas,
      size,
      time.value + 40,
      color.withValues(alpha: alpha),
      density: 0.35,
    );
  }

  @override
  bool shouldRepaint(_LooseDustPainter oldDelegate) =>
      oldDelegate.color != color;
}
