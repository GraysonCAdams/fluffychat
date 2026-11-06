// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:mime/mime.dart';

/// Wraps a pasted file path, typing it by its content when its name has no
/// known extension. Images copied from browsers and some apps reach the
/// clipboard as temp files named just "download", which would otherwise be
/// sent as an untyped attachment instead of an image.
///
/// Such a file is copied to a temp path with the matching extension, since
/// on native platforms an [XFile]'s name always comes from its path.
Future<XFile> pastedFile(String path) async {
  if (lookupMimeType(path) != null) return XFile(path);
  final header = await File(path)
      .openRead(0, defaultMagicNumbersMaxLength)
      .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
  final mimeType = lookupMimeType(path, headerBytes: header);
  if (mimeType == null) return XFile(path);

  final directory = await Directory.systemTemp.createTemp('pasted');
  final name =
      '${File(path).uri.pathSegments.last}.${extensionFromMime(mimeType)}';
  final typed = await File(
    path,
  ).copy('${directory.path}${Platform.pathSeparator}$name');
  return XFile(typed.path, mimeType: mimeType);
}
