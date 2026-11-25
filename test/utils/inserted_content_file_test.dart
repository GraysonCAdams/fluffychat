// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/utils/inserted_content_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final gif = Uint8List.fromList([0x47, 0x49, 0x46]);

  test('a native XFile built from bytes ignores name and has no filename', () {
    // Why the keyboard path sets path as well as name.
    final file = XFile.fromData(gif, mimeType: 'image/gif', name: 'image.gif');
    expect(file.name, '');
  });

  group('insertedContentFileName', () {
    test('adds the extension when the URI segment is an opaque id', () {
      expect(
        insertedContentFileName(
          'content://com.google.android.inputmethod.latin.fileprovider/gif/8f3a1c',
          'image/gif',
        ),
        '8f3a1c.gif',
      );
    });

    test('keeps a name that already has the extension', () {
      expect(
        insertedContentFileName(
          'content://provider/media/cat.GIF',
          'image/gif',
        ),
        'cat.GIF',
      );
    });

    test('prefers a fileName query parameter', () {
      expect(
        insertedContentFileName(
          'content://provider/inputContent?fileName=party.gif&mimeType=image%2Fgif',
          'image/gif',
        ),
        'party.gif',
      );
    });

    test('falls back to a generic name for an empty URI', () {
      expect(insertedContentFileName('', 'image/gif'), 'image.gif');
    });
  });

  test('insertedContentFile keeps its name on native platforms', () {
    final file = insertedContentFile(
      gif,
      'content://com.google.android.inputmethod.latin.fileprovider/gif/8f3a1c',
      'image/gif',
    );
    expect(file.name, '8f3a1c.gif');
    expect(file.mimeType, 'image/gif');
  });
}
