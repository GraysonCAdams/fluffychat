// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Measures where the unread count's digits land inside the badge when drawn
// with the bundled Google Sans Flex, using the badge's text style, the way a
// 20 px Container centres it, and the nudge the badge applies.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/pages/chat_list/unread_bubble.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _fonts = {
  'GoogleSansFlex Medium':
      'assets/fonts/google_sans_flex/GoogleSansFlex-Medium.ttf',
};

const _badgeHeight = 20.0;
const _ratio = 8.0;

/// Logical pixels the ink centre of [text] sits below the badge centre.
Future<double> digitOffset(String family, String text, TextStyle base) async {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: base.copyWith(fontFamily: family),
    ),
    textDirection: TextDirection.ltr,
    textHeightBehavior: const TextHeightBehavior(
      leadingDistribution: TextLeadingDistribution.even,
    ),
  )..layout();
  const w = 40.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(_ratio);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, w, _badgeHeight),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  // Container(alignment: center) puts the child's box in the middle.
  painter.paint(
    canvas,
    Offset(
      4,
      (_badgeHeight - painter.height) / 2 - unreadDigitNudge(base.fontSize!),
    ),
  );
  final image = await recorder.endRecording().toImage(
    (w * _ratio).round(),
    (_badgeHeight * _ratio).round(),
  );
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final pw = image.width;
  int? top, bottom;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < pw; x++) {
      if (data.getUint8((y * pw + x) * 4) < 128) {
        top ??= y;
        bottom = y;
        break;
      }
    }
  }
  return ((top! + bottom!) / 2 / _ratio) - _badgeHeight / 2;
}

const badgeStyle = TextStyle(
  color: ui.Color(0xFF000000),
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1,
  leadingDistribution: TextLeadingDistribution.even,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final entry in _fonts.entries) {
    test('digits are centred in the badge with ${entry.key}', () async {
      await ui.loadFontFromList(
        await File(entry.value).readAsBytes(),
        fontFamily: entry.key,
      );
      final offset = await digitOffset(entry.key, '3', badgeStyle);
      // ignore: avoid_print
      print(
        '${entry.key}: digit centre offset ${offset.toStringAsFixed(2)} px',
      );
      expect(offset.abs(), lessThan(0.1));
    }, skip: !File(entry.value).existsSync());
  }
}
