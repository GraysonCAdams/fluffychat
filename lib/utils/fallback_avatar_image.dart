// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';

/// A PNG of the placeholder [Avatar] draws for [name] when a chat has no
/// picture: its initials, or an icon for a bare phone number, on the
/// name's colour. For places outside the app that need an image, such as
/// the conversation shortcuts in Android's share sheet, which otherwise show
/// an empty grey circle.
///
/// The image is a full square, as an Android adaptive icon expects: the
/// system masks it to its own shape and may crop the outer sixth on each
/// side, so the initials stay inside the middle two thirds.
Future<Uint8List?> renderFallbackAvatar(String name, {int size = 216}) async {
  final letters = Avatar.calcFallbackLetters(name);
  final colors = letters.colorScheme;
  final icon = Avatar.numberIcon(name);
  final dimension = size.toDouble();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, dimension, dimension),
    Paint()..color = colors.primaryContainer,
  );
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    text: icon != null
        ? TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              fontSize: dimension / 3,
              color: colors.onPrimaryContainer,
            ),
          )
        : TextSpan(
            text: letters,
            style: TextStyle(
              fontFamily: 'RobotoMono',
              fontWeight: FontWeight.bold,
              fontSize: dimension / 3.75,
              color: colors.onPrimaryContainer,
            ),
          ),
  )..layout(maxWidth: dimension);
  painter.paint(
    canvas,
    Offset((dimension - painter.width) / 2, (dimension - painter.height) / 2),
  );
  final image = await recorder.endRecording().toImage(size, size);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
