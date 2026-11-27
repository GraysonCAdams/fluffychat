// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// How far the user's own message has got, as its status mark shows it.
enum StatusMarkState { sending, sent, readBySome, read, failed }

/// What a message still on its way shows: a spinning arc under a bubble, a
/// clock in the chat list.
enum StatusMarkSending { spinner, clock }

/// M3's emphasized decelerate easing.
const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);

/// The delivery mark of the user's own message, in one neutral colour.
///
/// Sent is a circled check. Read is told by shape alone: a second ring
/// slides out from behind the first ([StatusMarkState.readBySome], some of
/// a group), then both fill with the checks knocked out
/// ([StatusMarkState.read]). The states lie on one scale (0 sending, 1
/// sent, 2 read by some, 3 read), so a change to a later state plays every
/// step between in one run: sending to read draws the check on, slides the
/// second ring out and fills both. A failed message cross-fades to the
/// error icon, the only colour the mark takes.
///
/// Only live changes animate: the mark is built in its current state, so a
/// message scrolled back into view does not replay its history, and with
/// reduced motion every change is instant.
class StatusMark extends StatefulWidget {
  final StatusMarkState state;
  final Color color;
  final StatusMarkSending sending;
  final IconData errorIcon;

  const StatusMark({
    super.key,
    required this.state,
    required this.color,
    this.sending = StatusMarkSending.spinner,
    this.errorIcon = Icons.error_outlined,
  });

  static const double size = 16;

  /// How far the second ring slides out from behind the first.
  static const double overlap = 7;

  /// Where [state] lies on the mark's scale.
  static double levelOf(StatusMarkState state) => switch (state) {
    StatusMarkState.sending || StatusMarkState.failed => 0,
    StatusMarkState.sent => 1,
    StatusMarkState.readBySome => 2,
    StatusMarkState.read => 3,
  };

  /// How long the change from [from] to [to] on the scale takes: 250 ms to
  /// draw the check on, 300 ms to slide the second ring out and fill both.
  static Duration durationBetween(double from, double to) {
    double span(double lo, double hi) =>
        (to.clamp(lo, hi) - from.clamp(lo, hi)).abs() / (hi - lo);
    final ms = 250 * span(0, 1) + 300 * span(1, 3);
    return Duration(milliseconds: ms.round());
  }

  @override
  State<StatusMark> createState() => _StatusMarkState();
}

class _StatusMarkState extends State<StatusMark> with TickerProviderStateMixin {
  late final AnimationController _level = AnimationController(
    vsync: this,
    upperBound: 3,
    value: StatusMark.levelOf(widget.state),
  );
  late final AnimationController _error = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: widget.state == StatusMarkState.failed ? 1 : 0,
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// The arc only spins while it shows.
  void _syncSpin() {
    final spinning =
        widget.sending == StatusMarkSending.spinner &&
        _level.value < 1 &&
        _error.value < 1;
    if (spinning && !_spin.isAnimating) _spin.repeat();
    if (!spinning && _spin.isAnimating) _spin.stop();
  }

  @override
  void initState() {
    super.initState();
    _level.addListener(_syncSpin);
    _error.addListener(_syncSpin);
    _syncSpin();
  }

  @override
  void didUpdateWidget(StatusMark old) {
    super.didUpdateWidget(old);
    if (old.state == widget.state) return;
    final target = StatusMark.levelOf(widget.state);
    final failed = widget.state == StatusMarkState.failed;
    if (MediaQuery.disableAnimationsOf(context)) {
      _level.value = target;
      _error.value = failed ? 1 : 0;
    } else {
      _level.animateTo(
        target,
        duration: StatusMark.durationBetween(_level.value, target),
        curve: emphasizedDecelerate,
      );
      failed ? _error.forward() : _error.reverse();
    }
    _syncSpin();
  }

  @override
  void dispose() {
    _level.dispose();
    _error.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_level, _error, _spin]),
        builder: (context, _) {
          final second = (_level.value - 1).clamp(0.0, 1.0);
          final width = StatusMark.size + StatusMark.overlap * second;
          final error = Curves.easeOut.transform(_error.value);
          return SizedBox(
            width: width,
            height: StatusMark.size,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: AlignmentDirectional.centerEnd,
              children: [
                if (error < 1)
                  Opacity(
                    opacity: 1 - error,
                    child: Transform.scale(
                      scale: 1 - 0.4 * error,
                      child: CustomPaint(
                        size: Size(width, StatusMark.size),
                        painter: StatusMarkPainter(
                          level: _level.value,
                          spin: _spin.value,
                          color: widget.color,
                          sending: widget.sending,
                          rtl: Directionality.of(context) == TextDirection.rtl,
                        ),
                      ),
                    ),
                  ),
                if (error > 0)
                  Opacity(
                    opacity: error,
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * error,
                      child: Icon(
                        widget.errorIcon,
                        size: StatusMark.size,
                        color: errorColor,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Paints the mark at [level] on its scale (see [StatusMark]).
class StatusMarkPainter extends CustomPainter {
  final double level;

  /// The spinning arc's turn, 0 to 1.
  final double spin;
  final Color color;
  final StatusMarkSending sending;
  final bool rtl;

  const StatusMarkPainter({
    required this.level,
    required this.spin,
    required this.color,
    required this.sending,
    this.rtl = false,
  });

  static const double _radius = 6.6;
  static const double _stroke = 1.5;

  /// The gap of background around the front ring, as wide as the cutouts
  /// of the reader stack and the group collage.
  static const double cutout = 1.5;

  Path _check(Offset c) => Path()
    ..moveTo(c.dx - 3.0, c.dy + 0.1)
    ..lineTo(c.dx - 0.9, c.dy + 2.2)
    ..lineTo(c.dx + 3.1, c.dy - 1.8);

  /// The first [t] of [path]'s length, for a stroke that draws on.
  static Path _trim(Path path, double t) {
    final out = Path();
    if (t <= 0) return out;
    final metrics = path.computeMetrics().toList();
    var left = metrics.fold<double>(0, (sum, m) => sum + m.length) * t;
    for (final metric in metrics) {
      final take = math.min(left, metric.length);
      out.addPath(metric.extractPath(0, take), Offset.zero);
      left -= take;
      if (left <= 0) break;
    }
    return out;
  }

  void _ring(Canvas canvas, Offset c, {required double draw, double fill = 0}) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final rect = Rect.fromCircle(center: c, radius: _radius);
    if (sending == StatusMarkSending.clock) {
      // The clock's face is the ring; its hands fade as the check draws on.
      canvas.drawCircle(c, _radius, stroke);
      if (draw < 1) {
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - 3.6)
            ..lineTo(c.dx, c.dy)
            ..lineTo(c.dx + 2.6, c.dy + 1.4),
          Paint.from(stroke)
            ..color = color.withValues(alpha: color.a * (1 - draw)),
        );
      }
    } else {
      // A quarter arc that spins, grown by the draw-on to the whole ring as
      // it settles at 12 o'clock.
      final sweep = (0.25 + 0.75 * draw) * 2 * math.pi;
      final start = spin * 2 * math.pi * (1 - draw) - math.pi / 2 * draw;
      canvas.drawArc(rect, start, sweep, false, stroke);
    }
    final check = _trim(_check(c), ((draw - 0.35) / 0.65).clamp(0.0, 1.0));
    canvas.drawPath(check, stroke);
    if (fill > 0) {
      // The fill sweeps out from the centre, the check knocked out of it.
      final disc = (_radius + _stroke / 2) * fill;
      canvas.drawCircle(c, disc, Paint()..color = color);
      canvas.save();
      canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: c, radius: disc)),
      );
      canvas.drawPath(check, stroke..blendMode = BlendMode.clear);
      canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final draw = level.clamp(0.0, 1.0);
    final second = (level - 1).clamp(0.0, 1.0);
    final fill = (level - 2).clamp(0.0, 1.0);
    // The second ring comes out after the first in the reading direction.
    final dir = rtl ? -1.0 : 1.0;
    final back = Offset(
      rtl ? size.width - _radius - 1.4 : _radius + 1.4,
      size.height / 2,
    );
    final front = back.translate(dir * StatusMark.overlap * second, 0);
    canvas.saveLayer(Offset.zero & size, Paint());
    _ring(canvas, back, draw: draw, fill: fill);
    if (second > 0) {
      canvas.drawCircle(
        front,
        _radius + _stroke / 2 + cutout,
        Paint()..blendMode = BlendMode.clear,
      );
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(0, 0, 0, second),
      );
      _ring(canvas, front, draw: 1, fill: fill);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(StatusMarkPainter old) =>
      old.level != level ||
      old.spin != spin ||
      old.color != color ||
      old.sending != sending ||
      old.rtl != rtl;
}
