// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:matrix/matrix.dart';

/// The pixel size of the encoded image in [bytes], read from its header
/// without decoding the pixels. Null when the bytes are not an image the
/// engine can read.
Future<({int width, int height})?> encodedImageSize(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 || descriptor.height <= 0) return null;
    return (width: descriptor.width, height: descriptor.height);
  } catch (e) {
    Logs().d('Unable to read the size of an image', e);
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
