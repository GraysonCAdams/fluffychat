// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/utils/resize_video.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('displayedVideoSize', () {
    test('a portrait phone clip, stored as rotated landscape frames, '
        'shows portrait', () {
      final size = displayedVideoSize(3840, 2160, 90);
      expect(size.width, 2160);
      expect(size.height, 3840);
      final other = displayedVideoSize(3840, 2160, 270);
      expect(other.width, 2160);
      expect(other.height, 3840);
    });

    test('an upright or upside-down clip keeps its frame size', () {
      for (final rotation in [null, 0, 180]) {
        final size = displayedVideoSize(1920, 1080, rotation);
        expect(size.width, 1920);
        expect(size.height, 1080);
      }
    });

    test('an unknown size stays unknown', () {
      final size = displayedVideoSize(null, null, 90);
      expect(size.width, isNull);
      expect(size.height, isNull);
    });
  });

  test(
    'a video thumbnail carries its pixel size into thumbnail_info',
    () async {
      final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 54, height: 96)),
      );
      final thumbnail = await videoThumbnailFile(jpeg, 'clip.mp4');
      expect(thumbnail.width, 54);
      expect(thumbnail.height, 96);
      expect(thumbnail.info['w'], 54);
      expect(thumbnail.info['h'], 96);
    },
  );
}
