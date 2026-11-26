// SPDX-FileCopyrightText: 2026 Grayson Adams
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

/// Records an animation of the real widgets as measurements over time and
/// a strip of frames, for the website to compare its animations with. See
/// README.md in this folder.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

/// Reads the rectangle of one part of the screen in logical pixels, or
/// null while that part is not built.
typedef RectReader = Rect? Function();

/// One animation to record: what to measure in each frame, how long it
/// runs and which part of the screen its frame strip shows.
class AnimationSpec {
  final String name;

  /// The Dart file and widget that animate.
  final String source;
  final int endMs;
  final Map<String, RectReader> rects;

  /// Parts whose fill colour is read in each frame.
  final Map<String, Finder> colors;
  final Map<String, String? Function()> texts;

  /// The regions of the screen the strip shows, read once in the trigger's
  /// frame and stacked top to bottom.
  final List<Rect> Function() crop;

  const AnimationSpec({
    required this.name,
    required this.source,
    required this.endMs,
    required this.rects,
    required this.crop,
    this.colors = const {},
    this.texts = const {},
  });
}

/// The times sampled, in milliseconds after the trigger: every 50 ms to
/// [endMs], and every 16 ms through the first 300 ms.
List<int> sampleTimes(int endMs) {
  final times = <int>{
    for (var t = 0; t <= endMs; t += 50) t,
    for (var t = 0; t < 300 && t <= endMs; t += 16) t,
  };
  return times.toList()..sort();
}

/// The rectangle of the first widget [finder] finds, or null.
RectReader rectOf(WidgetTester tester, Finder finder) => () {
  final found = _evaluate(finder);
  if (found.isEmpty) return null;
  final box = found.first.renderObject;
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
};

/// Runs [trigger], pumps the frame it lands in (t = 0) and then the
/// sample times of [spec], measuring each frame. Writes
/// `anim/<name>.json` and `anim/<name>.png` under `--update-goldens`;
/// otherwise checks the measurements against the JSON file there.
Future<void> recordAnimation(
  WidgetTester tester,
  AnimationSpec spec,
  Future<void> Function() trigger, {
  double pixelRatio = 2.625,
  Map<String, Object?> notes = const {},
}) async {
  await trigger();
  await tester.pump();
  final crop = spec.crop();
  final frames = <Map<String, Object?>>[];
  final strip = <RgbaImage>[];
  final stripTimes = <int>[];
  var now = 0;
  for (final t in sampleTimes(spec.endMs)) {
    if (t > now) {
      await tester.pump(Duration(milliseconds: t - now));
      now = t;
    }
    frames.add({
      't': t,
      'rects': {
        for (final MapEntry(:key, :value) in spec.rects.entries)
          key: _rectJson(value()),
      },
      if (spec.colors.isNotEmpty)
        'colors': {
          for (final MapEntry(:key, :value) in spec.colors.entries)
            key: _colorOf(value),
        },
      if (spec.texts.isNotEmpty)
        'texts': {
          for (final MapEntry(:key, :value) in spec.texts.entries) key: value(),
        },
    });
    if (t % 50 == 0) {
      strip.add(await captureParityRegions(tester, crop, pixelRatio));
      stripTimes.add(t);
    }
  }
  final json = {
    'name': spec.name,
    'source': spec.source,
    'notes': {
      'times': 'ms after the trigger; t=0 is the frame the trigger lands in',
      'strip':
          'anim/${spec.name}.png shows the frames at the stripTimes, left '
          'to right, at ${pixelRatio}x, cropped to the crop regions '
          '(logical px) stacked top to bottom',
      ...notes,
    },
    'stripTimes': stripTimes,
    'crop': [for (final rect in crop) _rectJson(rect)],
    'frames': frames,
  };
  final text = '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  final file = File('$parityDir/anim/${spec.name}.json');
  if (autoUpdateGoldenFiles) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
    File(
      '$parityDir/anim/${spec.name}.png',
    ).writeAsBytesSync(encodeRgbaPng(stackRgba(strip, vertical: false)));
  } else {
    expect(
      text,
      file.readAsStringSync(),
      reason: '${spec.name} moves differently from ${file.path}',
    );
  }
}

/// What [finder] finds, or nothing where a `.first` or `.at()` finder has
/// nothing to pick from.
List<Element> _evaluate(Finder finder) {
  try {
    return finder.evaluate().toList();
  } on StateError {
    return const [];
  } on RangeError {
    return const [];
  }
}

List<double>? _rectJson(Rect? rect) => rect == null
    ? null
    : [
        for (final value in [rect.left, rect.top, rect.width, rect.height])
          double.parse(value.toStringAsFixed(2)),
      ];

/// The fill of the first painted box at or under what [finder] finds: a
/// decoration's colour or a material's, as `#RRGGBB` (`#RRGGBBAA` while
/// not opaque).
String? _colorOf(Finder finder) {
  final found = _evaluate(finder);
  if (found.isEmpty) return null;
  Color? color;
  void visit(RenderObject object) {
    if (color != null) return;
    if (object is RenderDecoratedBox) {
      final decoration = object.decoration;
      if (decoration is BoxDecoration && decoration.color != null) {
        color = decoration.color;
        return;
      }
    }
    if (object is RenderPhysicalShape && object.color.a > 0) {
      color = object.color;
      return;
    }
    if (object is RenderPhysicalModel && object.color.a > 0) {
      color = object.color;
      return;
    }
    object.visitChildren(visit);
  }

  final root = found.first.renderObject;
  if (root != null) visit(root);
  final c = color;
  if (c == null) return null;
  String hex(double v) =>
      (v * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${hex(c.r)}${hex(c.g)}${hex(c.b)}${c.a < 1 ? hex(c.a) : ''}';
}
