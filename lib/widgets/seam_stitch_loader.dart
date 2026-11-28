// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// The Seam loading animation: the logo, sewing.
///
/// A quiet loop: the four stitches draw on one by one from left to right,
/// the loose end of the thread sways slightly, the mark rests for a breath
/// and the stitches dissolve. The needle stays tucked behind the bubble and
/// gives two slow, small wiggles in place; the working thread moves only
/// with it. One loop takes [SeamStitchMotion.loop] seconds.
///
/// While [loading] is true it loops. When [loading] turns false it carries
/// on to the end of the current pass, stops on the logo pose, calls
/// [onLanded] and crossfades to [settled] (if given). With reduced motion
/// it shows the logo pose and does not move.
///
/// The mark is drawn in [color], with stitches and gaps cut out so that
/// whatever is behind shows through: white on Seam Cobalt for the start
/// screen, as the app icon has it, or the glyph's faint colour on the
/// surface for the desktop's empty pane. [pale] fills the piece of fabric
/// above the seam, as the brand's two-tone mark has it: see
/// [SeamStitchPainter.periwinkle], [SeamStitchPainter.lighter] and
/// [SeamStitchPainter.faded] for the colour to pass.
///
/// The mark is laid out as in the app icon and the glyph assets: a square
/// [size] box holds the icon's 432-unit artboard, so `seam_glyph.png` at the
/// same size lines up with it exactly.
class SeamStitchLoader extends StatefulWidget {
  final double size;
  final Color color;
  final Color? pale;
  final bool loading;

  /// Where in the loop to begin, in seconds. The default is the logo pose,
  /// so the loader takes over from a static logo without a jump.
  final double startAt;

  /// Shown in place of the loader once it has landed, by a 0.5 s crossfade.
  final Widget? settled;
  final VoidCallback? onLanded;

  const SeamStitchLoader({
    super.key,
    this.size = 192,
    this.color = Colors.white,
    this.pale,
    this.loading = true,
    this.startAt = SeamStitchMotion.tSew,
    this.settled,
    this.onLanded,
  });

  @override
  State<SeamStitchLoader> createState() => SeamStitchLoaderState();
}

class SeamStitchLoaderState extends State<SeamStitchLoader>
    with TickerProviderStateMixin {
  final SeamStitchMotion motion = SeamStitchMotion();
  final _repaint = _Repaint();
  late final Ticker _ticker = createTicker(_tick);
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  Duration _last = Duration.zero;
  double _tau = 0;
  bool _finishing = false;
  bool _done = false;
  bool _reduced = false;

  /// Seconds into the loop.
  @visibleForTesting
  double get tau => _tau;

  /// Whether the loader has landed on the logo pose and stopped.
  @visibleForTesting
  bool get landed => _done;

  @override
  void initState() {
    super.initState();
    if (widget.loading) {
      _restart();
    } else {
      motion.land();
      _done = true;
      _fade.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(SeamStitchLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading && !oldWidget.loading && (_done || _finishing)) {
      _restart();
    }
    _finishing = !widget.loading && !_done;
    _sync();
  }

  void _restart() {
    _done = false;
    _finishing = false;
    _tau = widget.startAt % SeamStitchMotion.loop;
    motion.clock = 0;
    motion.evalAt(_tau);
    _fade.value = 0;
    _repaint.notify();
  }

  /// Starts or stops the ticker to match the state, and applies reduced
  /// motion: the logo pose, held still, and no crossfade.
  void _sync() {
    if (_reduced) {
      _ticker.stop();
      if (!_done) {
        motion.land();
        _repaint.notify();
        if (!widget.loading) _landNow(animate: false);
      }
      return;
    }
    if (!_done && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = math.min(0.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    final before = _tau;
    _tau += dt;
    motion.clock += dt;
    if (_finishing &&
        before < SeamStitchMotion.tLand &&
        _tau >= SeamStitchMotion.tLand) {
      // The pass is complete: stay on the logo.
      motion.land();
      _landNow(animate: true);
    } else {
      if (_tau >= SeamStitchMotion.loop) _tau -= SeamStitchMotion.loop;
      motion.evalAt(_tau);
    }
    _repaint.notify();
  }

  void _landNow({required bool animate}) {
    _done = true;
    _finishing = false;
    _ticker.stop();
    if (animate) {
      _fade.forward();
    } else {
      _fade.value = 1;
    }
    widget.onLanded?.call();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _fade.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(widget.size),
      painter: SeamStitchPainter(
        motion: motion,
        ink: widget.color,
        pale: widget.pale,
        repaint: _repaint,
      ),
    );
    final settled = widget.settled;
    final Widget child;
    if (settled == null) {
      child = mark;
    } else {
      final curve = CurvedAnimation(parent: _fade, curve: Curves.ease);
      child = Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(opacity: ReverseAnimation(curve), child: mark),
          FadeTransition(opacity: curve, child: settled),
        ],
      );
    }
    return SizedBox.square(dimension: widget.size, child: child);
  }
}

class _Repaint extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// The geometry and timeline of the loader, apart from any drawing.
///
/// Coordinates are the 432-unit artboard of `brand/source/seam_mark.py`.
/// [evalAt] sets the pose for a moment of the loop; [land] sets the logo
/// pose. [clock] is the time since the loop began, which keeps running
/// across loops (the tail's sway follows it).
class SeamStitchMotion {
  static const List<Offset> seamPoints = [
    Offset(86, 212),
    Offset(150, 226),
    Offset(196, 214),
    Offset(230, 200),
    Offset(266, 186),
    Offset(316, 178),
    Offset(346, 188),
  ];

  // The needle: butt near the local origin, point at (nl, 0), eye centred
  // at (eyeX, 0).
  static final double nl = math.sqrt(108 * 108 + 108 * 108);
  static const double nh = 17;
  static final double ne = math.min(nl * .26, 34 * 1.3);
  static const double er = nh * .42;
  static final double eyeX = (5 + ne) / 2;
  static const double tw = 11;

  // Stitch k is cut out between seam parameters ua[k] and ub[k].
  static const List<double> ua = [0, 4 / 14, 8 / 14, 12 / 14];
  static const List<double> ub = [2 / 14, 6 / 14, 10 / 14, 1];

  // The needle rests as in the logo, eye out at the top right, point behind
  // the bubble. Twice in each loop, at wigAt, it gives one slow, small
  // wiggle in place: a lean each way of wigAng about the spot where it goes
  // behind the bubble (pivot, along the needle) and back to rest, with the
  // slightest draw outward along its own length.
  static const double needleAng = math.pi * .75;
  static const double needleX = 392, needleY = 58, pivot = 92, wig = .9;
  static const List<double> wigAt = [.45, 1.95];
  static const double wigAng = .044, wigOut = 1.5;

  // Timeline, in seconds. Stitch k starts at t0 + k * per and takes draw to
  // draw on. Then the finished mark rests (tSew..tLand), the stitches fade
  // out (..tIn), and after a short rest the loop starts over.
  static const double t0 = .15, per = .7, draw = .55;
  static const double tSew = t0 + 4 * per;
  static const double tLand = tSew + .8;
  static const double tIn = tLand + .55;
  static const double loop = tIn + .45;

  // The tail's sway: cycles per second, and radians each way.
  static const double swingHz = .35, swing = .035;

  // Within endR of a thread end the mark draws the thread on top of the
  // bubble, with no gap round it.
  static const double endR = 22;

  static final Offset root = seam(0);

  final List<double> cut = List.filled(4, 0);
  double cutA = 1, pulse = 1, still = 0, clock = 0, wiggleNow = 0, out = 0;

  /// The working thread's bezier: start (at the eye), two controls, end (on
  /// the seam). Set by [thread].
  final List<Offset> th = List.filled(4, Offset.zero);

  static double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
  static double _ss(double x) {
    x = _clamp01(x);
    return x * x * (3 - 2 * x);
  }

  static double _sine(double x) => .5 - .5 * math.cos(math.pi * _clamp01(x));
  static double _bz(double t, double a, double b, double c, double d) {
    final m = 1 - t;
    return m * m * m * a +
        3 * m * m * t * b +
        3 * m * t * t * c +
        t * t * t * d;
  }

  /// Material 3 emphasized-decelerate, cubic-bezier(.05, .7, .1, 1): y for a
  /// given x, by bisection on the curve parameter.
  static double decel(double x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 24; i++) {
      final m = (lo + hi) / 2;
      if (_bz(m, 0, .05, .1, 1) < x) {
        lo = m;
      } else {
        hi = m;
      }
    }
    return _bz((lo + hi) / 2, 0, .7, 1, 1);
  }

  /// The point at parameter [u] (0..1) along the seam's two cubic pieces.
  static Offset seam(double u) {
    u = _clamp01(u);
    final k = u < .5 ? 0 : 3;
    final t = u < .5 ? u * 2 : u * 2 - 1;
    const p = seamPoints;
    return Offset(
      _bz(t, p[k].dx, p[k + 1].dx, p[k + 2].dx, p[k + 3].dx),
      _bz(t, p[k].dy, p[k + 1].dy, p[k + 2].dy, p[k + 3].dy),
    );
  }

  static double _wiggle(double e) {
    final x = e / wig;
    if (x <= 0 || x >= 1) return 0;
    final h = math.sin(math.pi * x);
    return math.sin(2 * math.pi * x) * h * h / .65;
  }

  /// Sets the pose for [t] seconds into the loop.
  void evalAt(double t) {
    cutA = 1;
    pulse = 1;
    wiggleNow = _wiggle(t - wigAt[0]) + _wiggle(t - wigAt[1]);
    out = wiggleNow.abs();
    for (var k = 0; k < 4; k++) {
      cut[k] = ua[k] + (ub[k] - ua[k]) * decel((t - t0 - k * per) / draw);
    }
    still = t < tLand ? _ss((t - tSew + .45) / .45) : 1 - _ss((t - tLand) / .6);
    if (t >= tSew && t < tLand) {
      // one slow breath
      final w = math.sin(math.pi * (t - tSew) / (tLand - tSew));
      pulse = 1 + .01 * w * w;
    } else if (t >= tLand && t < tIn) {
      cutA = 1 - _sine((t - tLand) / (tIn - tLand));
    } else if (t >= tIn) {
      for (var k = 0; k < 4; k++) {
        cut[k] = ua[k];
      }
    }
  }

  /// The exact logo pose.
  void land() {
    evalAt(tSew);
    pulse = 1;
    still = 1;
  }

  /// The free tail hangs from the first stitch and sways as one piece, a few
  /// degrees about its root. Its shape is always the mark's own tail curve.
  double tailAngle() =>
      swing * (1 - still) * math.sin(2 * math.pi * swingHz * clock);

  /// The working thread: the mark's curve from the eye, bowing out to the
  /// right, down to the end of the seam. That end never moves.
  void thread() {
    final s = seam(1);
    final ex = 216 + (s.dx - 216) * pulse, ey = 206 + (s.dy - 206) * pulse;
    // Its upper end is tied at the eye, so it goes where the needle's
    // wiggle takes the eye.
    final a = needleAng + wiggleNow * wigAng;
    final r = eyeX - pivot - out * wigOut;
    final px = needleX + math.cos(needleAng) * pivot + math.cos(a) * r;
    final py = needleY + math.sin(needleAng) * pivot + math.sin(a) * r;
    th[0] = Offset(px, py);
    th[1] = Offset(px + 30, py + 26);
    th[2] = Offset(ex + 34, ey - 40);
    th[3] = Offset(ex, ey);
  }
}

/// Paints [motion]'s current pose.
///
/// Everything is painted in [ink] in a layer of its own, and outlines,
/// stitches and gaps are erased from it, so whatever is behind shows
/// through. [pale], when given, fills the bubble above the seam.
///
/// The colours follow brand/BRAND.md: [periwinkle] with a white bubble on
/// cobalt, [lighter] with a coloured bubble on a surface, [faded] with a
/// neutral glyph that stands in for a tinted `seam_glyph.png`.
class SeamStitchPainter extends CustomPainter {
  final SeamStitchMotion motion;
  final Color ink;
  final Color? pale;

  SeamStitchPainter({
    required this.motion,
    required this.ink,
    this.pale,
    super.repaint,
  });

  /// Seam Pale: the piece above the seam when the bubble is white.
  static const Color periwinkle = Color(0xFF9ABAF0);

  /// The piece above the seam for a bubble in [ink]: [ink] 30% of the way
  /// to white on a light surface (cobalt gives the brand's #5F8CE3), 45% on
  /// a dark one, where the theme's primary is already light.
  static Color lighter(Color ink, {required bool dark}) =>
      Color.lerp(ink, Colors.white, dark ? .45 : .3)!;

  /// The piece above the seam for a one-colour glyph: [ink] at 55% opacity,
  /// as the glyph assets draw it, so the mark matches `seam_glyph.png`
  /// tinted the same colour.
  static Color faded(Color ink) => ink.withValues(alpha: ink.a * .55);

  static final Path _ellipse = Path()
    ..addOval(
      Rect.fromCenter(center: const Offset(216, 206), width: 264, height: 216),
    );
  static final Path _tailShape = Path()
    ..moveTo(112, 262)
    ..cubicTo(110, 292, 98, 320, 72, 342)
    ..cubicTo(118, 340, 156, 320, 180, 294)
    ..close();
  static final Path _shape = Path.combine(
    PathOperation.union,
    _ellipse,
    _tailShape,
  );
  // the region below the seam (BELOW in brand/source/seam_mark.py)
  static final Path _below = Path()
    ..moveTo(86, 212)
    ..cubicTo(150, 226, 196, 214, 230, 200)
    ..cubicTo(266, 186, 316, 178, 346, 188)
    ..lineTo(470, 188)
    ..lineTo(470, 470)
    ..lineTo(-20, 470)
    ..lineTo(-20, 212)
    ..close();
  static final Path _needle = () {
    const nh = SeamStitchMotion.nh, er = SeamStitchMotion.er;
    final nl = SeamStitchMotion.nl, ne = SeamStitchMotion.ne;
    return Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(-6, 0)
      ..cubicTo(-6, -nh, 10, -nh, 26, -nh * .86)
      ..lineTo(nl * .7, -nh * .5)
      ..lineTo(nl, 0)
      ..lineTo(nl * .7, nh * .5)
      ..lineTo(26, nh * .86)
      ..cubicTo(10, nh, -6, nh, -6, 0)
      ..close()
      ..moveTo(5, -er)
      ..lineTo(ne, -er)
      ..arcToPoint(Offset(ne, er), radius: const Radius.circular(er))
      ..lineTo(5, er)
      ..arcToPoint(const Offset(5, -er), radius: const Radius.circular(er))
      ..close();
  }();
  static final Path _tail = () {
    final r = SeamStitchMotion.root;
    return Path()
      ..moveTo(r.dx, r.dy)
      ..cubicTo(
        r.dx - 34,
        r.dy + 2,
        r.dx - 46,
        r.dy + 34,
        r.dx - 30,
        r.dy + 62,
      );
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final m = motion..thread();
    final k = size.width / 432;
    final ink = Paint()
      ..color = this.ink
      ..isAntiAlias = true;
    Paint stroke(Paint p, double width) => Paint()
      ..color = p.color
      ..blendMode = p.blendMode
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final erase = Paint()
      ..color = const Color(0xFF000000)
      ..blendMode = BlendMode.dstOut;
    final threadPath = Path()
      ..moveTo(m.th[0].dx, m.th[0].dy)
      ..cubicTo(
        m.th[1].dx,
        m.th[1].dy,
        m.th[2].dx,
        m.th[2].dy,
        m.th[3].dx,
        m.th[3].dy,
      );

    // The mark sits at .81 scale in the icon and the glyph.
    void frame() {
      canvas.scale(k);
      canvas.translate(216, 216);
      canvas.scale(.81);
      canvas.translate(-216, -206);
    }

    canvas.saveLayer(Offset.zero & size, Paint());

    // Needle and working thread, behind the bubble and parted from it by a
    // gap.
    canvas.save();
    frame();
    canvas.drawPath(threadPath, stroke(ink, SeamStitchMotion.tw));
    canvas.save();
    canvas.translate(SeamStitchMotion.needleX, SeamStitchMotion.needleY);
    canvas.rotate(SeamStitchMotion.needleAng);
    canvas.translate(SeamStitchMotion.pivot, 0);
    canvas.rotate(m.wiggleNow * SeamStitchMotion.wigAng);
    canvas.translate(
      -SeamStitchMotion.pivot - m.out * SeamStitchMotion.wigOut,
      0,
    );
    canvas.drawPath(_needle, ink);
    canvas.restore();
    canvas.restore();

    // The cloth; the bubble also carries the breath.
    canvas.save();
    frame();
    canvas.translate(216, 206);
    canvas.scale(m.pulse);
    canvas.translate(-216, -206);
    canvas.drawPath(_shape, erase);
    canvas.drawPath(_ellipse, stroke(erase, 30));
    canvas.drawPath(_tailShape, stroke(erase, 30));
    // bubble: with [pale], the whole bubble in pale and the piece below the
    // seam over it in ink, so a translucent pale replaces the ink above the
    // seam rather than tinting it, and the halves meet without a hairline
    final pale = this.pale;
    if (pale == null) {
      canvas.drawPath(_shape, ink);
    } else {
      canvas.drawPath(_shape, Paint()..color = pale);
      canvas.save();
      canvas.clipPath(_below);
      canvas.drawPath(_shape, ink);
      canvas.restore();
    }
    // stitches, cut out as far as each has been drawn
    final stitch = stroke(erase, 16)
      ..color = Color.fromRGBO(0, 0, 0, m.cutA.clamp(0.0, 1.0));
    for (var i = 0; i < 4; i++) {
      final a = SeamStitchMotion.ua[i], e = m.cut[i];
      if (e - a <= .0005) continue;
      final p = Path();
      for (var j = 0; j <= 10; j++) {
        final s = SeamStitchMotion.seam(a + (e - a) * j / 10);
        j == 0 ? p.moveTo(s.dx, s.dy) : p.lineTo(s.dx, s.dy);
      }
      canvas.drawPath(p, stitch);
    }
    // the free tail, with a gap around it where it crosses the bubble
    final root = SeamStitchMotion.root;
    final angle = m.tailAngle();
    void aboutRoot() {
      canvas.translate(root.dx, root.dy);
      canvas.rotate(angle);
      canvas.translate(-root.dx, -root.dy);
    }

    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(const Rect.fromLTWH(-200, -200, 900, 900))
        ..addOval(Rect.fromCircle(center: root, radius: SeamStitchMotion.endR)),
    );
    aboutRoot();
    canvas.drawPath(_tail, stroke(erase, SeamStitchMotion.tw + 6));
    canvas.restore();
    canvas.save();
    aboutRoot();
    canvas.drawPath(_tail, stroke(ink, SeamStitchMotion.tw));
    canvas.restore();
    canvas.restore();

    // The working thread comes onto the bubble at its end on the seam,
    // drawn straight over it.
    canvas.save();
    frame();
    canvas.clipPath(
      Path()..addOval(
        Rect.fromCircle(center: m.th[3], radius: SeamStitchMotion.endR),
      ),
    );
    canvas.drawPath(threadPath, stroke(ink, SeamStitchMotion.tw));
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(SeamStitchPainter oldDelegate) =>
      oldDelegate.motion != motion ||
      oldDelegate.ink != ink ||
      oldDelegate.pale != pale;
}
