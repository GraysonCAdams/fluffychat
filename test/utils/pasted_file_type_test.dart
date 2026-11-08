// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:fluffychat/utils/pasted_file_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pasted_file_type'));
  tearDown(() => dir.deleteSync(recursive: true));

  const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  test('an extensionless image is typed by its content', () async {
    final path = '${dir.path}${Platform.pathSeparator}download';
    File(path).writeAsBytesSync([...pngSignature, 0, 0, 0, 13]);
    final file = await pastedFile(path);
    expect(file.mimeType, 'image/png');
    expect(file.name, 'download.png');
  });

  test('a file with an extension is left as is', () async {
    final path = '${dir.path}${Platform.pathSeparator}photo.jpg';
    File(path).writeAsBytesSync([...pngSignature]);
    final file = await pastedFile(path);
    expect(file.mimeType, isNull);
    expect(file.name, 'photo.jpg');
  });

  test('pasted PNG bytes become a named image', () {
    final file = pastedImageData(
      Uint8List.fromList([...pngSignature, 0, 0, 0, 13]),
    );
    expect(file.mimeType, 'image/png');
    expect(file.name, 'image.png');
  });

  test('pasted JPEG bytes become a named image', () {
    final file = pastedImageData(
      Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]),
    );
    expect(file.mimeType, 'image/jpeg');
    expect(file.name, startsWith('image.'));
  });

  test('unrecognised content keeps its name', () async {
    final path = '${dir.path}${Platform.pathSeparator}notes';
    File(path).writeAsStringSync('plain text');
    final file = await pastedFile(path);
    expect(file.mimeType, isNull);
    expect(file.name, 'notes');
  });
}
