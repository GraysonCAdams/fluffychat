// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Draws [child] on [background] at twice the logical size and returns its
/// pixels as RGBA bytes, row by row, with the width in physical pixels.
Future<(Uint8List, int)> renderPixels(
  WidgetTester tester,
  Widget child, {
  required Color background,
  Size size = const Size(64, 64),
  Brightness brightness = Brightness.dark,
}) async {
  const pixelRatio = 2.0;
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.fromSize(
            size: size,
            child: ColoredBox(
              color: background,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    ),
  );
  final bytes = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  });
  return (bytes!, (size.width * pixelRatio).round());
}

/// The largest difference from [color] of any channel of any pixel.
int maxDeviation(Uint8List rgba, Color color) {
  final target = [
    (color.r * 255).round(),
    (color.g * 255).round(),
    (color.b * 255).round(),
  ];
  var worst = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      final d = (rgba[i + c] - target[c]).abs();
      if (d > worst) worst = d;
    }
  }
  return worst;
}

/// The colours painted along the top and bottom edges of the message
/// bubble holding [text], inside its padding and clear of its round
/// corners, read from the layer of the nearest repaint boundary above it.
/// A bubble in one flat colour gives that colour at every point.
Future<List<Color>> bubbleEdgeColors(WidgetTester tester, Finder text) async {
  final bubble = find
      .ancestor(
        of: text,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).borderRadius is BorderRadius &&
              w.clipBehavior == Clip.antiAlias,
        ),
      )
      .first;
  final box = tester.renderObject<RenderBox>(bubble);
  RenderObject boundary = box;
  while (!boundary.isRepaintBoundary) {
    boundary = boundary.parent!;
  }
  final rect = box.localToGlobal(Offset.zero, ancestor: boundary) & box.size;
  final layer = boundary.debugLayer! as OffsetLayer;
  final bytes = await tester.runAsync(() async {
    final image = await layer.toImage(boundary.paintBounds);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (data!.buffer.asUint8List(), image.width);
  });
  final (rgba, width) = bytes!;
  final origin = boundary.paintBounds.topLeft;
  Color at(double x, double y) {
    final i = (((y - origin.dy).floor()) * width + (x - origin.dx).floor()) * 4;
    return Color.fromARGB(rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2]);
  }

  return [
    for (var x = rect.left + 22; x < rect.right - 22; x += 4) ...[
      at(x, rect.top + 2),
      at(x, rect.bottom - 3),
    ],
  ];
}
