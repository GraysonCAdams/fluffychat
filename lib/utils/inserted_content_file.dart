// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:mime/mime.dart';

/// A file name for content a keyboard inserted (a GIF or sticker from
/// Gboard and similar), always ending in the extension of its MIME type.
///
/// Keyboards hand over a `content://` URI whose last segment is often an
/// opaque id with no extension. A GIF sent with no file name reached iMessage
/// recipients through the bridge as a generic "file" rather than an image.
String insertedContentFileName(String uri, String? mimeType) {
  final parsed = Uri.tryParse(uri);
  var name =
      parsed?.queryParameters['fileName'] ??
      (parsed != null && parsed.pathSegments.isNotEmpty
          ? parsed.pathSegments.last
          : uri.split('/').last.split('?').first);
  if (name.trim().isEmpty) name = 'image';
  final extension = mimeType == null ? null : extensionFromMime(mimeType);
  if (extension != null &&
      !name.toLowerCase().endsWith('.${extension.toLowerCase()}')) {
    name = '$name.$extension';
  }
  return name;
}

/// The bytes a keyboard inserted, as a file that keeps its name.
///
/// Native [XFile]s built from bytes take their name from `path` and ignore
/// `name`, so both are set.
XFile insertedContentFile(Uint8List data, String uri, String? mimeType) {
  final name = insertedContentFileName(uri, mimeType);
  return XFile.fromData(data, mimeType: mimeType, name: name, path: name);
}
