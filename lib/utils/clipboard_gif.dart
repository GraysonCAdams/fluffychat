// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cross_file/cross_file.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';

/// The animated GIF behind a clipboard that holds a single linked `<img>`,
/// or null when the clipboard holds anything else.
///
/// GIF pickers such as the Windows emoji panel (Win+.) and browsers put a
/// GIF on the clipboard as HTML pointing at the file, alongside a bitmap of
/// its first frame. Pasting the bitmap would send a still image, so the GIF
/// itself is downloaded instead.
Future<XFile?> clipboardLinkedGif() async {
  try {
    final markup = await Pasteboard.html;
    if (markup == null) return null;
    final images = html.parse(markup).querySelectorAll('img');
    if (images.length != 1) return null;
    final uri = Uri.tryParse(images.single.attributes['src'] ?? '');
    if (uri == null ||
        !uri.isScheme('https') ||
        !uri.path.toLowerCase().endsWith('.gif')) {
      return null;
    }

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final bytes = response.bodyBytes;
    if (lookupMimeType('', headerBytes: bytes) != 'image/gif') return null;
    final name = uri.pathSegments.last;
    // Native XFiles take their name from the path; the bytes stay in memory.
    return XFile.fromData(bytes, mimeType: 'image/gif', name: name, path: name);
  } catch (e, s) {
    Logs().w('Unable to fetch the GIF linked from the clipboard', e, s);
    return null;
  }
}
