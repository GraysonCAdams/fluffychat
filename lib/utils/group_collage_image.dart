// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';

/// One member in a [renderGroupCollage]: the [image] bytes of the
/// picture, or none for the initials of [name] on its colour.
typedef CollageMember = ({String name, Uint8List? image});

/// A transparent PNG of up to four [members] as small round avatars, the
/// collage Google Messages shows for a group without a picture: two on a
/// diagonal, three in a cluster, four in a grid. The faces take up the
/// middle [fill] of the square, the rest left clear. Returns null for fewer
/// than two members.
Future<Uint8List?> renderGroupCollage(
  List<CollageMember> members, {
  int size = 128,
  double fill = 1,
}) async {
  if (members.length < 2) return null;
  final shown = members.take(4).toList();
  final dimension = size * fill;
  final margin = Offset(1, 1) * ((size - dimension) / 2);
  final face = switch (shown.length) {
    2 => dimension * 0.62,
    3 => dimension * 0.52,
    _ => dimension * 0.48,
  };
  final far = dimension - face;
  final centers = switch (shown.length) {
    2 => [Offset.zero, Offset(far, far)],
    3 => [Offset(far / 2, 0), Offset(0, far), Offset(far, far)],
    _ => [Offset.zero, Offset(far, 0), Offset(0, far), Offset(far, far)],
  };

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (final (i, member) in shown.indexed) {
    final rect = (centers[i] + margin) & Size(face, face);
    final circle = RRect.fromRectAndRadius(rect, Radius.circular(face / 2));
    canvas.save();
    canvas.clipRRect(circle, doAntiAlias: true);
    ui.Image? picture;
    if (member.image != null) {
      try {
        final codec = await ui.instantiateImageCodec(
          member.image!,
          targetWidth: face.round(),
          targetHeight: face.round(),
        );
        picture = (await codec.getNextFrame()).image;
        codec.dispose();
      } catch (_) {
        picture = null;
      }
    }
    if (picture != null) {
      canvas.drawImageRect(
        picture,
        Rect.fromLTWH(
          0,
          0,
          picture.width.toDouble(),
          picture.height.toDouble(),
        ),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      picture.dispose();
    } else {
      final letters = Avatar.calcFallbackLetters(member.name);
      final colors = letters.avatarColors;
      canvas.drawRect(rect, Paint()..color = colors.fill);
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: letters,
          style: TextStyle(
            fontFamily: 'GoogleSansFlex',
            fontWeight: FontWeight.bold,
            fontSize: face / 2.6,
            color: colors.onFill,
          ),
        ),
      )..layout(maxWidth: face);
      painter.paint(
        canvas,
        rect.center - Offset(painter.width / 2, painter.height / 2),
      );
    }
    canvas.restore();
  }
  final image = await recorder.endRecording().toImage(size, size);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
