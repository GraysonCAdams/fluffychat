// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Optical centring for one-line centred text. Glyphs carry different
/// empty space on their left and right ("G" against "n"), so text centred
/// by its advance can sit up to a pixel off the axis. This measures where a
/// line's ink actually falls by drawing it once off-screen, laid out exactly
/// as [OpticalLine] draws it, and scanning the pixels; the correction is
/// cached per string. The engine's line metrics are not used: for a line
/// cut with an ellipsis they leave the ellipsis out, which put such lines
/// several pixels off.
abstract final class OpticalCentre {
  static const _cacheSize = 512;

  /// Pixels this faint or fainter do not count as ink (alpha out of 255).
  static const _inkAlpha = 40;

  /// Insertion-ordered, so the first key is the least recently used.
  static final _cache = <String, double>{};
  static final _pending = <String, Future<double>>{};

  static String _key(
    String text,
    TextStyle style,
    TextScaler scaler,
    double maxWidth,
    double dpr,
  ) =>
      '${style.fontFamily}|${scaler.scale(style.fontSize ?? 14)}|'
      '${style.fontWeight}|${style.letterSpacing}|'
      '${maxWidth.toStringAsFixed(1)}|$dpr|$text';

  /// The horizontal shift that puts the ink of [text] on its box's centre,
  /// or null when it has not been measured yet.
  static double? lookup(
    String text,
    TextStyle style,
    TextScaler scaler,
    double maxWidth,
    double dpr,
  ) {
    final key = _key(text, style, scaler, maxWidth, dpr);
    final hit = _cache.remove(key);
    if (hit != null) _cache[key] = hit;
    return hit;
  }

  /// Measures the shift for [text] laid out exactly as [OpticalLine] draws
  /// it: one centred line within [maxWidth], cut with an ellipsis.
  static Future<double> measure(
    String text,
    TextStyle style,
    TextScaler scaler,
    double maxWidth,
    double dpr,
  ) {
    final key = _key(text, style, scaler, maxWidth, dpr);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    // A failed measurement leaves the line advance-centred.
    return _pending[key] ??= _measure(text, style, scaler, maxWidth, dpr)
        .catchError((Object _) => 0.0)
        .then((shift) {
          _pending.remove(key);
          _cache[key] = shift;
          if (_cache.length > _cacheSize) _cache.remove(_cache.keys.first);
          return shift;
        });
  }

  static Future<double> _measure(
    String text,
    TextStyle style,
    TextScaler scaler,
    double maxWidth,
    double dpr,
  ) async {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(color: const Color(0xFFFFFFFF)),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: scaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    const pad = 8.0;
    final width = ((painter.width + pad * 2) * dpr).ceil();
    final height = (painter.height * dpr).ceil();
    final boxCentre = painter.width / 2;
    if (width <= 0 || height <= 0) {
      painter.dispose();
      return 0;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    painter.paint(canvas, const Offset(pad, 0));
    painter.dispose();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return 0;
    var minX = width;
    var maxX = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width * 4;
      for (var x = 0; x < width; x++) {
        if (data.getUint8(row + x * 4 + 3) > _inkAlpha) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
      }
    }
    if (maxX < minX) return 0;
    final inkCentre = (minX + maxX + 1) / 2 / dpr - pad;
    return boxCentre - inkCentre;
  }
}

/// One line of centred text, cut with an ellipsis, whose visible ink sits
/// on the centre axis (see [OpticalCentre]). The first frame draws it
/// advance-centred; it settles once the measurement lands, a frame later.
class OpticalLine extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double maxWidth;

  /// The width the correction is looked up at. It equals [maxWidth] at
  /// rest; while a line's width animates, callers pass the nearer resting
  /// width so nothing is measured on every frame.
  final double opticalWidth;

  const OpticalLine(
    this.text, {
    required this.style,
    required this.maxWidth,
    double? opticalWidth,
    super.key,
  }) : opticalWidth = opticalWidth ?? maxWidth;

  @override
  State<OpticalLine> createState() => _OpticalLineState();
}

class _OpticalLineState extends State<OpticalLine> {
  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final shift = OpticalCentre.lookup(
      widget.text,
      widget.style,
      scaler,
      widget.opticalWidth,
      dpr,
    );
    if (shift == null) {
      OpticalCentre.measure(
        widget.text,
        widget.style,
        scaler,
        widget.opticalWidth,
        dpr,
      ).then((_) {
        if (mounted) setState(() {});
      });
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: Transform.translate(
        offset: Offset(shift ?? 0, 0),
        child: Text(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: widget.style,
        ),
      ),
    );
  }
}
