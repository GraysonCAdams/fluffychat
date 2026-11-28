// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Placeholder payloads as mautrix-gmessages attaches them, built by hand.

List<int> _varint(int value) {
  final out = <int>[];
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

/// One protobuf field: a varint for an int, length-delimited otherwise.
List<int> protoField(int number, Object value) => switch (value) {
  final int v => [..._varint(number << 3), ..._varint(v)],
  final String v => protoField(number, utf8.encode(v)),
  final List<int> v => [
    ..._varint(number << 3 | 2),
    ..._varint(v.length),
    ...v,
  ],
  _ => throw ArgumentError(value),
};

/// A `MediaContent` with the fields the bridge fills in for a placeholder.
List<int> mediaContent({
  required String name,
  String mimeType = 'image/jpeg',
  int? width,
  int? height,
  List<int>? preview,
}) => [
  ...protoField(1, 1),
  ...protoField(4, name),
  ...protoField(5, 2400000),
  if (width != null && height != null)
    ...protoField(6, [...protoField(1, width), ...protoField(2, height)]),
  ...?(preview == null ? null : protoField(7, preview)),
  ...protoField(14, mimeType),
];

/// `fi.mau.gmessages.raw_debug_data` for a message with [media] parts: the
/// envelope's field 3, its field 2, then the `Message` with one
/// `MessageInfo` (field 10, media in its field 3) per part.
String rawDebugData(List<List<int>> media) {
  final message = [
    ...protoField(1, 'msg-1'),
    for (final m in media) ...protoField(10, [...protoField(3, m)]),
    ...protoField(11, 4),
  ];
  return base64.encode([
    ...protoField(1, 7),
    ...protoField(3, [...protoField(2, message)]),
  ]);
}

/// A small JPEG, [width] by [height], of a sky over a green hill, like the
/// bridge's previews (about 60 pixels across).
Uint8List previewJpeg({int width = 47, int height = 63}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final hill = y > height * 0.6 - (x - width / 2).abs() * 0.3;
      image.setPixelRgb(
        x,
        y,
        hill ? 46 : 30 + y * 2,
        hill ? 125 : 136 + y,
        hill ? 50 : 229,
      );
    }
  }
  return img.encodeJpg(image, quality: 70);
}
